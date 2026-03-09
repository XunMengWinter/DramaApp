import AVFoundation
import SwiftUI

struct DramaEpisodePagerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playbackManager: PlaybackManager

    let drama: Drama
    let initialEpisodeNumber: Int

    @State private var selectedEpisodeNumber: Int?
    @State private var fullscreenEpisode: Episode?

    private let playbackRates: [Float] = [0.75, 1.0, 1.25, 1.5, 2.0, 3.0]

    private var episodes: [Episode] {
        drama.sortedEpisodes
    }

    private var currentEpisode: Episode? {
        guard let selectedEpisodeNumber else { return episodes.first }
        return episodes.first(where: { $0.episodeNumber == selectedEpisodeNumber }) ?? episodes.first
    }

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .top) {
                Color.black.ignoresSafeArea()

                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(episodes) { episode in
                            EpisodePageView(
                                drama: drama,
                                episode: episode,
                                isActive: selectedEpisodeNumber == episode.episodeNumber && fullscreenEpisode == nil,
                                containerHeight: proxy.size.height,
                                onTapFullscreen: {
                                    fullscreenEpisode = episode
                                }
                            )
                            .id(episode.episodeNumber)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $selectedEpisodeNumber)

                topBar
            }
        }
        .onAppear {
            if selectedEpisodeNumber == nil {
                let validEpisodeNumbers = Set(episodes.map(\.episodeNumber))
                selectedEpisodeNumber = validEpisodeNumbers.contains(initialEpisodeNumber)
                    ? initialEpisodeNumber
                    : episodes.first?.episodeNumber
            }
            playSelectedEpisodeIfNeeded()
        }
        .onChange(of: selectedEpisodeNumber) { _, _ in
            playSelectedEpisodeIfNeeded()
        }
        .fullScreenCover(item: $fullscreenEpisode) { episode in
            LandscapeFullscreenPlayerView(drama: drama, episode: episode)
        }
    }

    private var topBar: some View {
        HStack {
            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.headline)
                    .foregroundStyle(.white)
                    .padding(12)
                    .background(Color.black.opacity(0.45), in: Circle())
            }

            Spacer()

            Menu {
                ForEach(playbackRates, id: \.self) { rate in
                    Button {
                        playbackManager.playbackRate = rate
                    } label: {
                        if playbackManager.playbackRate == rate {
                            Label("\(rateString(rate))x", systemImage: "checkmark")
                        } else {
                            Text("\(rateString(rate))x")
                        }
                    }
                }
            } label: {
                Text("倍速")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 8)
                    .background(Color.black.opacity(0.45), in: Capsule())
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
    }

    private func rateString(_ rate: Float) -> String {
        if rate == floor(rate) {
            return String(format: "%.1f", rate)
        }
        return String(rate)
    }

    private func playSelectedEpisodeIfNeeded() {
        guard let episode = currentEpisode else { return }
        playbackManager.play(drama: drama, episode: episode)
    }
}

private struct EpisodePageView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager

    let drama: Drama
    let episode: Episode
    let isActive: Bool
    let containerHeight: CGFloat
    let onTapFullscreen: () -> Void

    private var shouldShowFullscreenButton: Bool {
        episode.aspectRatio >= (4.0 / 3.0)
    }

    private var isCurrentActivePlayer: Bool {
        isActive && playbackManager.isCurrent(dramaId: drama.id, episodeNumber: episode.episodeNumber)
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            if isCurrentActivePlayer {
                ZStack {
                    SharedVideoPlayerView(videoGravity: .resizeAspectFill)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .clipped()

                    if !playbackManager.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 72))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 8)
                    }
                }
            } else {
                posterBackground
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.82)],
                startPoint: .center,
                endPoint: .bottom
            )

            if isCurrentActivePlayer {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playbackManager.togglePlayback()
                    }
            }

            VStack(alignment: .leading, spacing: 8) {
                if shouldShowFullscreenButton {
                    HStack {
                        Spacer()
                        Button(action: onTapFullscreen) {
                            Text("全屏观看")
                                .font(.subheadline.weight(.semibold))
                                .foregroundStyle(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 9)
                                .background(Color.white.opacity(0.2), in: Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.bottom, 10)
                }

                Text(episode.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)

                Text("第\(episode.episodeNumber)集 / 共\(max(drama.totalEpisodes, drama.episodes.count))集")
                    .font(.footnote)
                    .foregroundStyle(.white.opacity(0.85))

                if !drama.description.isEmpty {
                    Text(drama.description)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.8))
                        .lineLimit(3)
                }
            }
            .allowsHitTesting(false)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 16)
            .padding(.bottom, 42)
        }
        .frame(maxWidth: .infinity)
        .frame(height: containerHeight)
        .background(Color.black)
    }

    @ViewBuilder
    private var posterBackground: some View {
        if let posterURL = drama.posterURL {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    fallbackPoster
                case .empty:
                    ProgressView()
                        .tint(.white)
                @unknown default:
                    fallbackPoster
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .clipped()
        } else {
            fallbackPoster
        }
    }

    private var fallbackPoster: some View {
        LinearGradient(
            colors: [Color.black, Color.gray.opacity(0.55)],
            startPoint: .top,
            endPoint: .bottom
        )
    }
}

struct LandscapeFullscreenPlayerView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var playbackManager: PlaybackManager

    let drama: Drama
    let episode: Episode

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Color.black.ignoresSafeArea()

            GeometryReader { proxy in
                SharedVideoPlayerView()
                    .frame(width: proxy.size.height, height: proxy.size.width)
                    .rotationEffect(.degrees(90))
                    .position(x: proxy.size.width / 2, y: proxy.size.height / 2)
            }
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 26, weight: .bold))
                    .foregroundStyle(.white.opacity(0.88))
                    .padding(16)
            }
        }
        .statusBarHidden(true)
        .onAppear {
            playbackManager.play(drama: drama, episode: episode)
        }
    }
}
