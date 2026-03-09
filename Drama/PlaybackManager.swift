import AVFoundation
import Combine
import Foundation

@MainActor
final class PlaybackManager: ObservableObject {
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

    @Published private(set) var player = AVPlayer()
    @Published private(set) var currentSelection: PlaybackSelection?
    @Published private(set) var historyItems: [HistoryItem] = []
    @Published private(set) var isPlaying: Bool = false
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

    init() {
        player.actionAtItemEnd = .pause
        let interval = CMTime(seconds: 0.3, preferredTimescale: 600)
        periodicTimeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
            Task { @MainActor [weak self] in
                self?.saveCurrentProgress(at: time.seconds)
            }
        }
    }

    func updateCatalog(_ catalog: [String: Drama]) {
        catalogByDramaId = catalog
        rebuildHistoryItems()
    }

    func play(drama: Drama, episode: Episode, autoPlay: Bool = true) {
        guard let url = episode.videoURL else { return }

        let nextSelection = PlaybackSelection(dramaId: drama.id, episodeNumber: episode.episodeNumber)
        if currentSelection == nextSelection {
            lastPlayedAtByDramaId[drama.id] = Date()
            autoPlay ? resume() : pause()
            rebuildHistoryItems()
            return
        }

        saveCurrentProgress(at: player.currentTime().seconds)

        let item = AVPlayerItem(url: url)
        player.replaceCurrentItem(with: item)
        observeItemDidFinish(for: item)

        currentSelection = nextSelection
        lastPlayedAtByDramaId[drama.id] = Date()

        let key = EpisodeKey(dramaId: drama.id, episodeNumber: episode.episodeNumber)
        if let savedTime = episodeProgressByKey[key], savedTime > 0 {
            let seekTime = CMTime(seconds: savedTime, preferredTimescale: 600)
            player.seek(to: seekTime, toleranceBefore: .zero, toleranceAfter: .zero)
        }

        if autoPlay {
            resume()
        } else {
            player.pause()
            isPlaying = false
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
        episodeProgressByKey[key] = max(existingValue, seconds)
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
}
