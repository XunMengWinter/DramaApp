import CryptoKit
import Foundation

actor VideoCacheManager {
    struct CacheSummary {
        let totalBytes: Int64
        let fileCount: Int
        let limitBytes: Int64
    }

    private struct CacheIndex: Codable {
        var entries: [String: CacheEntry]
    }

    private struct CacheEntry: Codable {
        let remoteURL: String
        let localFileName: String
        var fileSize: Int64
        var lastAccessAt: Date
    }

    private let maxCacheSizeBytes: Int64 = 2 * 1024 * 1024 * 1024
    private let session: URLSession
    private let fileManager: FileManager

    private var initialized = false
    private var cacheDirectoryURL: URL
    private var indexFileURL: URL
    private var index: CacheIndex = .init(entries: [:])
    private var downloadTasks: [String: Task<Void, Never>] = [:]

    init(session: URLSession = URLSession(configuration: .default),
         fileManager: FileManager = .default) {
        self.session = session
        self.fileManager = fileManager

        let cachesDirectory = fileManager.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        cacheDirectoryURL = cachesDirectory.appendingPathComponent("VideoCache", isDirectory: true)
        indexFileURL = cacheDirectoryURL.appendingPathComponent("index.json", isDirectory: false)
    }

    func preparePlayableURL(for remoteURL: URL) async -> URL {
        guard isHTTPURL(remoteURL) else {
            return remoteURL
        }

        await ensureInitialized()

        let key = cacheKey(for: remoteURL)
        let hadStaleEntry = index.entries[key] != nil
        if let localURL = localURLIfAvailable(for: key) {
            touchEntry(forKey: key)
            await persistIndex()
            return localURL
        }
        if hadStaleEntry {
            await persistIndex()
        }

        startCachingIfNeeded(remoteURL: remoteURL, key: key)
        return remoteURL
    }

    func touchCachedAsset(for remoteURL: URL) async {
        guard isHTTPURL(remoteURL) else { return }
        await ensureInitialized()

        let key = cacheKey(for: remoteURL)
        guard localURLIfAvailable(for: key) != nil else { return }

        touchEntry(forKey: key)
        await persistIndex()
    }

    func cleanupIfNeeded() async {
        await ensureInitialized()
        await cleanupIndexAndLRU()
    }

    func cacheSummary() async -> CacheSummary {
        await ensureInitialized()
        await cleanupIndexAndLRU()

        let totalBytes = index.entries.values.reduce(Int64(0)) { partial, entry in
            partial + entry.fileSize
        }
        return CacheSummary(totalBytes: totalBytes, fileCount: index.entries.count, limitBytes: maxCacheSizeBytes)
    }

    func clearAllCache() async {
        await ensureInitialized()

        for task in downloadTasks.values {
            task.cancel()
        }
        downloadTasks.removeAll()

        for entry in index.entries.values {
            let fileURL = cacheDirectoryURL.appendingPathComponent(entry.localFileName, isDirectory: false)
            try? fileManager.removeItem(at: fileURL)
        }
        index.entries.removeAll()

        // Clean up possible orphan files while preserving index file.
        if let fileURLs = try? fileManager.contentsOfDirectory(at: cacheDirectoryURL, includingPropertiesForKeys: nil) {
            for fileURL in fileURLs where fileURL.lastPathComponent != indexFileURL.lastPathComponent {
                try? fileManager.removeItem(at: fileURL)
            }
        }

        await persistIndex()
    }

    private func ensureInitialized() async {
        guard !initialized else { return }
        initialized = true

        do {
            try fileManager.createDirectory(at: cacheDirectoryURL, withIntermediateDirectories: true, attributes: nil)
        } catch {
            return
        }

        guard fileManager.fileExists(atPath: indexFileURL.path) else {
            index = .init(entries: [:])
            await persistIndex()
            return
        }

        do {
            let data = try Data(contentsOf: indexFileURL)
            let decoded = try JSONDecoder().decode(CacheIndex.self, from: data)
            index = decoded
            await cleanupIndexAndLRU()
        } catch {
            index = .init(entries: [:])
            await persistIndex()
        }
    }

    private func startCachingIfNeeded(remoteURL: URL, key: String) {
        guard downloadTasks[key] == nil else { return }

        downloadTasks[key] = Task { [weak self, remoteURL, key] in
            await self?.downloadAndStore(remoteURL: remoteURL, key: key)
        }
    }

    private func downloadAndStore(remoteURL: URL, key: String) async {
        defer { downloadTasks[key] = nil }

        do {
            let (tempURL, response) = try await session.download(from: remoteURL)
            guard let httpResponse = response as? HTTPURLResponse,
                  (200 ... 299).contains(httpResponse.statusCode) else {
                return
            }

            guard !Task.isCancelled else { return }

            let destinationURL = cachedFileURL(for: remoteURL)
            try? fileManager.removeItem(at: destinationURL)

            do {
                try fileManager.moveItem(at: tempURL, to: destinationURL)
            } catch {
                // Cross-volume move fallback.
                try fileManager.copyItem(at: tempURL, to: destinationURL)
                try? fileManager.removeItem(at: tempURL)
            }

            let fileSize = fileSizeAtURL(destinationURL)
            guard fileSize > 0 else {
                try? fileManager.removeItem(at: destinationURL)
                return
            }
            guard !Task.isCancelled else {
                try? fileManager.removeItem(at: destinationURL)
                return
            }

            index.entries[key] = CacheEntry(
                remoteURL: remoteURL.absoluteString,
                localFileName: destinationURL.lastPathComponent,
                fileSize: fileSize,
                lastAccessAt: Date()
            )

            await persistIndex()
            await cleanupIndexAndLRU()
        } catch {
            // Download failures should not affect playback.
        }
    }

    private func localURLIfAvailable(for key: String) -> URL? {
        guard let entry = index.entries[key] else {
            return nil
        }

        let localURL = cacheDirectoryURL.appendingPathComponent(entry.localFileName, isDirectory: false)
        guard fileManager.fileExists(atPath: localURL.path), fileSizeAtURL(localURL) > 0 else {
            index.entries.removeValue(forKey: key)
            return nil
        }
        return localURL
    }

    private func touchEntry(forKey key: String) {
        guard var entry = index.entries[key] else { return }
        entry.lastAccessAt = Date()
        index.entries[key] = entry
    }

    private func cleanupIndexAndLRU() async {
        var validEntries: [String: CacheEntry] = [:]
        var totalSize: Int64 = 0

        for (key, entry) in index.entries {
            let url = cacheDirectoryURL.appendingPathComponent(entry.localFileName, isDirectory: false)
            let size = fileSizeAtURL(url)
            guard size > 0 else {
                try? fileManager.removeItem(at: url)
                continue
            }

            var updated = entry
            updated.fileSize = size
            validEntries[key] = updated
            totalSize += size
        }

        if totalSize > maxCacheSizeBytes {
            let sorted = validEntries.sorted { lhs, rhs in
                lhs.value.lastAccessAt < rhs.value.lastAccessAt
            }

            for (key, entry) in sorted where totalSize > maxCacheSizeBytes {
                let url = cacheDirectoryURL.appendingPathComponent(entry.localFileName, isDirectory: false)
                try? fileManager.removeItem(at: url)
                validEntries.removeValue(forKey: key)
                totalSize -= entry.fileSize
            }
        }

        index.entries = validEntries
        await persistIndex()
    }

    private func persistIndex() async {
        do {
            let data = try JSONEncoder().encode(index)
            try data.write(to: indexFileURL, options: .atomic)
        } catch {
            // Ignore index write failures; playback should continue.
        }
    }

    private func cacheKey(for remoteURL: URL) -> String {
        let digest = SHA256.hash(data: Data(remoteURL.absoluteString.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }

    private func cachedFileURL(for remoteURL: URL) -> URL {
        let key = cacheKey(for: remoteURL)
        let ext = remoteURL.pathExtension.isEmpty ? "mp4" : remoteURL.pathExtension
        return cacheDirectoryURL.appendingPathComponent("\(key).\(ext)", isDirectory: false)
    }

    private func fileSizeAtURL(_ url: URL) -> Int64 {
        guard let attributes = try? fileManager.attributesOfItem(atPath: url.path),
              let sizeNumber = attributes[.size] as? NSNumber else {
            return 0
        }
        return sizeNumber.int64Value
    }

    private func isHTTPURL(_ url: URL) -> Bool {
        guard let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "http" || scheme == "https"
    }
}
