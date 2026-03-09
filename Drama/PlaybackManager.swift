import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackManager: ObservableObject {
    private struct PersistedEpisodeProgress: Codable {
        let dramaId: String
        let episodeNumber: Int
        let progressSeconds: TimeInterval
    }

    private struct PersistedPlaybackState: Codable {
        let schemaVersion: Int
        let episodeProgresses: [PersistedEpisodeProgress]
        let lastPlayedAtByDramaId: [String: Date]
    }

    struct EpisodeKey: Hashable {
        let dramaId: String
        let episodeNumber: Int
    }

    struct PlaybackSelection: Equatable {
        let dramaId: String
        let episodeNumber: Int
    }

    struct HistoryItem: Identifiable {
        let dramaId: String
        let title: String
        let posterURL: URL?
        let progressValue: Double
        let watchedEpisodes: Int
        let totalEpisodes: Int
        let updatedAt: Date

        var id: String { dramaId }

        var progressText: String {
            "已观看 \(watchedEpisodes)/\(max(totalEpisodes, 1)) 集 · \(Int(progressValue * 100))%"
        }
    }

    struct CacheStatus {
        let usedBytes: Int64
        let fileCount: Int
        let limitBytes: Int64

        static let empty = CacheStatus(usedBytes: 0, fileCount: 0, limitBytes: 2 * 1024 * 1024 * 1024)
    }

    @Published private(set) var player = AVPlayer()
    @Published private(set) var currentSelection: PlaybackSelection?
    @Published private(set) var historyItems: [HistoryItem] = []
    @Published private(set) var isPlaying: Bool = false
    @Published private(set) var cacheStatus: CacheStatus = .empty
    @Published private(set) var isClearingCache = false
    @Published var playbackRate: Float = 1.0 {
        didSet {
            applyPlaybackRate()
        }
    }

    private var episodeProgressByKey: [EpisodeKey: TimeInterval] = [:]
    private var lastPlayedAtByDramaId: [String: Date] = [:]
    private var catalogByDramaId: [String: Drama] = [:]
    private var periodicTimeObserverToken: Any?
    private var itemDidFinishObserver: NSObjectProtocol?
    private var playRequestToken: UInt64 = 0
    private let videoCacheManager = VideoCacheManager()
    private var persistTask: Task<Void, Never>?
    private let fileManager = FileManager.default
    private let stateFileURL: URL = {
        let fm = FileManager.default
        let baseDirectory = fm.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? fm.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
        let stateDirectory = baseDirectory.appendingPathComponent("PlaybackState", isDirectory: true)
        return stateDirectory.appendingPathComponent("playback_state.json", isDirectory: false)
    }()

    init() {
        player.actionAtItemEnd = .pause
        let interval = CMTime(seconds: 0.3, preferredTimescale: 600)
        periodicTimeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.saveCurrentProgress(at: time.seconds)
            }
        }
        loadPersistedState()
        rebuildHistoryItems()
        Task {
            await refreshVideoCacheStatus()
        }
    }

    func updateCatalog(_ catalog: [String: Drama]) {
        catalogByDramaId = catalog
        rebuildHistoryItems()
    }

    func play(drama: Drama, episode: Episode, autoPlay: Bool = true) {
        guard let remoteURL = episode.videoURL else { return }

        let nextSelection = PlaybackSelection(dramaId: drama.id, episodeNumber: episode.episodeNumber)
        if currentSelection == nextSelection {
            lastPlayedAtByDramaId[drama.id] = Date()
            schedulePersistState()
            autoPlay ? resume() : pause()
            rebuildHistoryItems()
            return
        }

        saveCurrentProgress(at: player.currentTime().seconds)

        currentSelection = nextSelection
        lastPlayedAtByDramaId[drama.id] = Date()
        schedulePersistState()

        let key = EpisodeKey(dramaId: drama.id, episodeNumber: episode.episodeNumber)
        let savedTime = episodeProgressByKey[key] ?? 0
        playRequestToken &+= 1
        let currentToken = playRequestToken

        Task { [weak self] in
            guard let self else { return }
            let playableURL = await self.videoCacheManager.preparePlayableURL(for: remoteURL)
            await self.applyPlayRequest(
                playableURL: playableURL,
                remoteURL: remoteURL,
                savedTime: savedTime,
                autoPlay: autoPlay,
                token: currentToken
            )
        }

        rebuildHistoryItems()
    }

    func pause() {
        saveCurrentProgress(at: player.currentTime().seconds)
        player.pause()
        isPlaying = false
        rebuildHistoryItems()
    }

    func resume() {
        guard player.currentItem != nil else { return }
        player.play()
        player.rate = playbackRate
        isPlaying = true
    }

    func togglePlayback() {
        if isPlaying {
            pause()
        } else {
            resume()
        }
    }

    func currentEpisodeNumber(in dramaId: String) -> Int? {
        if let selection = currentSelection, selection.dramaId == dramaId {
            return selection.episodeNumber
        }
        guard let drama = catalogByDramaId[dramaId] else {
            return nil
        }
        return latestWatchedEpisodeNumber(in: drama)
    }

    func preferredEpisode(in drama: Drama) -> Episode {
        let episodes = drama.sortedEpisodes
        guard let first = episodes.first else {
            return Episode(episodeNumber: 1,
                           title: "第1集",
                           videoUrl: "",
                           duration: 0,
                           aspectRatio: 9.0 / 16.0)
        }

        if let selection = currentSelection,
           selection.dramaId == drama.id,
           let selectedEpisode = episodes.first(where: { $0.episodeNumber == selection.episodeNumber }) {
            return selectedEpisode
        }

        if let watchedNumber = latestWatchedEpisodeNumber(in: drama),
           let watchedEpisode = episodes.first(where: { $0.episodeNumber == watchedNumber }) {
            return watchedEpisode
        }

        return first
    }

    func isCurrent(dramaId: String, episodeNumber: Int) -> Bool {
        currentSelection == PlaybackSelection(dramaId: dramaId, episodeNumber: episodeNumber)
    }

    func progress(for drama: Drama) -> Double {
        let episodes = drama.sortedEpisodes
        let totalDuration = episodes.reduce(0.0) { partial, episode in
            partial + max(Double(episode.duration), 1)
        }
        guard totalDuration > 0 else {
            return 0
        }

        let watchedDuration = episodes.reduce(0.0) { partial, episode in
            let key = EpisodeKey(dramaId: drama.id, episodeNumber: episode.episodeNumber)
            let watched = episodeProgressByKey[key] ?? 0
            let episodeDuration = max(Double(episode.duration), 1)
            return partial + min(max(watched, 0), episodeDuration)
        }

        return min(max(watchedDuration / totalDuration, 0), 1)
    }

    func watchedEpisodesCount(for drama: Drama) -> Int {
        drama.sortedEpisodes.reduce(0) { partial, episode in
            let key = EpisodeKey(dramaId: drama.id, episodeNumber: episode.episodeNumber)
            let watched = episodeProgressByKey[key] ?? 0
            return partial + (watched > 2 ? 1 : 0)
        }
    }

    func refreshVideoCacheStatus() async {
        let summary = await videoCacheManager.cacheSummary()
        cacheStatus = CacheStatus(
            usedBytes: summary.totalBytes,
            fileCount: summary.fileCount,
            limitBytes: summary.limitBytes
        )
    }

    func clearVideoCache() async {
        guard !isClearingCache else { return }
        isClearingCache = true
        await videoCacheManager.clearAllCache()
        await refreshVideoCacheStatus()
        isClearingCache = false
    }

    private func latestWatchedEpisodeNumber(in drama: Drama) -> Int? {
        let watchedEpisodes = drama.sortedEpisodes.filter {
            let key = EpisodeKey(dramaId: drama.id, episodeNumber: $0.episodeNumber)
            return (episodeProgressByKey[key] ?? 0) > 2
        }
        return watchedEpisodes.map(\.episodeNumber).max()
    }

    private func saveCurrentProgress(at seconds: Double) {
        guard seconds.isFinite, seconds >= 0, let selection = currentSelection else {
            return
        }

        let key = EpisodeKey(dramaId: selection.dramaId, episodeNumber: selection.episodeNumber)
        let existingValue = episodeProgressByKey[key] ?? 0
        let updatedValue = max(existingValue, seconds)
        episodeProgressByKey[key] = updatedValue
        if updatedValue != existingValue {
            schedulePersistState()
        }
    }

    private func observeItemDidFinish(for item: AVPlayerItem) {
        if let token = itemDidFinishObserver {
            NotificationCenter.default.removeObserver(token)
        }
        itemDidFinishObserver = NotificationCenter.default.addObserver(
            forName: .AVPlayerItemDidPlayToEndTime,
            object: item,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let self else { return }
                if let duration = self.player.currentItem?.duration.seconds, duration.isFinite {
                    self.saveCurrentProgress(at: duration)
                }
                self.isPlaying = false
                self.rebuildHistoryItems()
            }
        }
    }

    private func applyPlaybackRate() {
        guard player.timeControlStatus == .playing else { return }
        player.rate = playbackRate
    }

    private func applyPlayRequest(playableURL: URL,
                                  remoteURL: URL,
                                  savedTime: TimeInterval,
                                  autoPlay: Bool,
                                  token: UInt64) async {
        guard token == playRequestToken else {
            return
        }

        let item = AVPlayerItem(url: playableURL)
        player.replaceCurrentItem(with: item)
        observeItemDidFinish(for: item)

        if savedTime > 0 {
            let seekTime = CMTime(seconds: savedTime, preferredTimescale: 600)
            await player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if autoPlay {
            resume()
        } else {
            player.pause()
            isPlaying = false
        }

        Task {
            await videoCacheManager.touchCachedAsset(for: remoteURL)
        }
        rebuildHistoryItems()
    }

    private func rebuildHistoryItems() {
        let sortedIds = lastPlayedAtByDramaId
            .sorted(by: { $0.value > $1.value })
            .map(\.key)

        historyItems = sortedIds.compactMap { dramaId in
            guard let drama = catalogByDramaId[dramaId], let updatedAt = lastPlayedAtByDramaId[dramaId] else {
                return nil
            }

            let progressValue = progress(for: drama)
            guard progressValue > 0 else {
                return nil
            }

            return HistoryItem(
                dramaId: drama.id,
                title: drama.title,
                posterURL: drama.posterURL,
                progressValue: progressValue,
                watchedEpisodes: watchedEpisodesCount(for: drama),
                totalEpisodes: max(drama.totalEpisodes, drama.episodes.count),
                updatedAt: updatedAt
            )
        }
    }

    private func loadPersistedState() {
        guard fileManager.fileExists(atPath: stateFileURL.path) else { return }
        guard let data = try? Data(contentsOf: stateFileURL) else { return }
        guard let decoded = try? JSONDecoder().decode(PersistedPlaybackState.self, from: data) else { return }
        guard decoded.schemaVersion == 1 else { return }

        var progressMap: [EpisodeKey: TimeInterval] = [:]
        for item in decoded.episodeProgresses where item.progressSeconds > 0 {
            let key = EpisodeKey(dramaId: item.dramaId, episodeNumber: item.episodeNumber)
            progressMap[key] = max(progressMap[key] ?? 0, item.progressSeconds)
        }

        episodeProgressByKey = progressMap
        lastPlayedAtByDramaId = decoded.lastPlayedAtByDramaId
    }

    private func schedulePersistState() {
        guard persistTask == nil else { return }
        persistTask = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.persistTask = nil }
            try? await Task.sleep(nanoseconds: 800_000_000)
            if Task.isCancelled { return }
            self.persistStateNow()
        }
    }

    private func persistStateNow() {
        let state = PersistedPlaybackState(
            schemaVersion: 1,
            episodeProgresses: episodeProgressByKey.map {
                PersistedEpisodeProgress(
                    dramaId: $0.key.dramaId,
                    episodeNumber: $0.key.episodeNumber,
                    progressSeconds: $0.value
                )
            },
            lastPlayedAtByDramaId: lastPlayedAtByDramaId
        )

        do {
            try fileManager.createDirectory(
                at: stateFileURL.deletingLastPathComponent(),
                withIntermediateDirectories: true,
                attributes: nil
            )
            let data = try JSONEncoder().encode(state)
            try data.write(to: stateFileURL, options: .atomic)
        } catch {
            // Ignore persistence failures and keep playback functional.
        }
    }
}
