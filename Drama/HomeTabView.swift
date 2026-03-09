import SwiftUI

struct HomeTabView: View {
    @EnvironmentObject private var viewModel: DramaAppViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    @State private var selectedDramaId: String?
    @State private var presentingDrama: Drama?

    private var dramas: [Drama] {
        viewModel.displayHomeDramas
    }

    private var currentDrama: Drama? {
        guard let selectedDramaId else { return dramas.first }
        return dramas.first(where: { $0.id == selectedDramaId }) ?? dramas.first
    }

    var body: some View {
        Group {
            if viewModel.isLoading && dramas.isEmpty {
                LoadingFillView(title: "正在加载短剧")
            } else if let message = viewModel.errorMessage, dramas.isEmpty {
                ErrorFillView(message: message) {
                    Task {
                        await viewModel.reload()
                    }
                }
            } else {
                mainContent
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            playbackManager.updateCatalog(viewModel.allDramasById)
            if selectedDramaId == nil {
                selectedDramaId = dramas.first?.id
            }
            playSelectedDramaIfNeeded()
        }
        .onChange(of: viewModel.displayHomeDramas.map(\.id)) { _, ids in
            if let selectedDramaId, ids.contains(selectedDramaId) {
                return
            }
            self.selectedDramaId = ids.first
        }
        .onChange(of: selectedDramaId) { _, _ in
            playSelectedDramaIfNeeded()
        }
        .onDisappear {
            playbackManager.pause()
        }
        .fullScreenCover(item: $presentingDrama) { drama in
            DramaEpisodePagerView(
                drama: drama,
                initialEpisodeNumber: playbackManager.currentEpisodeNumber(in: drama.id)
                    ?? playbackManager.preferredEpisode(in: drama).episodeNumber
            )
        }
    }

    private var mainContent: some View {
        GeometryReader { proxy in
            ZStack(alignment: .bottom) {
                ScrollView(.vertical) {
                    LazyVStack(spacing: 0) {
                        ForEach(dramas) { drama in
                            HomeDramaPage(
                                drama: drama,
                                isActive: selectedDramaId == drama.id && presentingDrama == nil,
                                pageHeight: proxy.size.height + proxy.safeAreaInsets.top,
                                episode: playbackManager.preferredEpisode(in: drama)
                            )
                            .id(drama.id)
                        }
                    }
                    .scrollTargetLayout()
                }
                .scrollTargetBehavior(.paging)
                .scrollIndicators(.hidden)
                .scrollPosition(id: $selectedDramaId)
                .ignoresSafeArea(edges: .top)

                if let drama = currentDrama {
                    homeBottomAction(drama: drama)
                }
            }
            .background(Color.black)
        }
    }

    private func homeBottomAction(drama: Drama) -> some View {
        Button {
            presentingDrama = drama
        } label: {
            HStack(spacing: 10) {
                Text("观看完整短剧 · 全\(max(drama.totalEpisodes, drama.episodes.count))集")
                    .font(.headline)
                    .foregroundStyle(.white)
                Spacer()
                Image(systemName: "chevron.right")
                    .foregroundStyle(.white.opacity(0.9))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)
            .background(.ultraThinMaterial)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.25))
    }

    private func playSelectedDramaIfNeeded() {
        guard presentingDrama == nil else { return }
        guard let drama = currentDrama else {
            playbackManager.pause()
            return
        }
        let preferredEpisode = playbackManager.preferredEpisode(in: drama)
        playbackManager.play(drama: drama, episode: preferredEpisode)
    }
}

private struct HomeDramaPage: View {
    @EnvironmentObject private var playbackManager: PlaybackManager

    let drama: Drama
    let isActive: Bool
    let pageHeight: CGFloat
    let episode: Episode

    private var isCurrentActivePlayer: Bool {
        isActive && playbackManager.currentSelection?.dramaId == drama.id
    }

    var body: some View {
        ZStack(alignment: .bottomLeading) {
            Color.black
                .ignoresSafeArea()

            if isCurrentActivePlayer {
                ZStack {
                    SharedVideoPlayerView()
                        .ignoresSafeArea()

                    if !playbackManager.isPlaying {
                        Image(systemName: "play.circle.fill")
                            .font(.system(size: 68))
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(radius: 8)
                    }
                }
            } else {
                DramaPosterView(drama: drama, aspectRatio: max(episode.aspectRatio, 0.4))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            LinearGradient(
                colors: [.clear, .black.opacity(0.78)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 260)

            VStack(alignment: .leading, spacing: 8) {
                Spacer()
                Text(drama.title)
                    .font(.title3.bold())
                    .foregroundStyle(.white)
                    .lineLimit(2)
                if !drama.tags.isEmpty {
                    DramaTagRow(tags: drama.tags)
                }
                if !drama.description.isEmpty {
                    Text(drama.description)
                        .font(.footnote)
                        .foregroundStyle(.white.opacity(0.88))
                        .lineLimit(2)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 86)

            if isCurrentActivePlayer {
                Color.clear
                    .contentShape(Rectangle())
                    .onTapGesture {
                        playbackManager.togglePlayback()
                    }
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: pageHeight)
        .clipped()
    }
}
