import SwiftUI

struct TheaterTabView: View {
    @EnvironmentObject private var viewModel: DramaAppViewModel
    @EnvironmentObject private var playbackManager: PlaybackManager

    @State private var selectedCategoryId: String?
    @State private var presentingDrama: Drama?
    @State private var isShowingSearchPage = false

    private var categories: [TheaterCategory] {
        viewModel.theaterCategories
    }

    var body: some View {
        Group {
            if viewModel.isLoading && categories.isEmpty {
                LoadingFillView(title: "正在加载剧场")
            } else if let message = viewModel.errorMessage, categories.isEmpty {
                ErrorFillView(message: message) {
                    Task {
                        await viewModel.reload()
                    }
                }
            } else {
                content
            }
        }
        .task {
            await viewModel.loadIfNeeded()
            playbackManager.updateCatalog(viewModel.allDramasById)
            if selectedCategoryId == nil {
                selectedCategoryId = categories.first?.id
            }
        }
        .onChange(of: viewModel.theaterCategories.map(\.id)) { _, ids in
            if let selectedCategoryId, ids.contains(selectedCategoryId) {
                return
            }
            self.selectedCategoryId = ids.first
        }
        .onChange(of: presentingDrama) { _, _ in
            if presentingDrama != nil {
                playbackManager.pause()
            }
        }
        .fullScreenCover(item: $presentingDrama, onDismiss: {
            // Returning to Theater should not leave video/audio playing in background.
            playbackManager.pause()
        }) { drama in
            DramaEpisodePagerView(
                drama: drama,
                initialEpisodeNumber: playbackManager.currentEpisodeNumber(in: drama.id)
                    ?? playbackManager.preferredEpisode(in: drama).episodeNumber
            )
        }
        .sheet(isPresented: $isShowingSearchPage) {
            SearchPlaceholderView()
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            searchBar
                .padding(.horizontal, 16)
                .padding(.top, 10)
                .padding(.bottom, 12)

            categorySelector
                .padding(.bottom, 8)

            categoryPages
        }
        .background(Color(.systemBackground))
    }

    private var searchBar: some View {
        Button {
            isShowingSearchPage = true
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(.secondary)
                Text("搜索短剧")
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 10))
        }
        .buttonStyle(.plain)
    }

    private var categorySelector: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(categories) { category in
                    Button {
                        withAnimation(.easeInOut(duration: 0.2)) {
                            selectedCategoryId = category.id
                        }
                    } label: {
                        VStack(spacing: 5) {
                            Text(category.titleZh)
                                .font(.subheadline.weight(selectedCategoryId == category.id ? .semibold : .regular))
                                .foregroundStyle(selectedCategoryId == category.id ? Color.primary : Color.secondary)
                            Capsule()
                                .fill(selectedCategoryId == category.id ? Color.primary : .clear)
                                .frame(height: 2)
                        }
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
    }

    private var categoryPages: some View {
        TabView(selection: $selectedCategoryId) {
            ForEach(categories) { category in
                ScrollView {
                    LazyVGrid(columns: [GridItem(.flexible(), spacing: 12), GridItem(.flexible(), spacing: 12)], spacing: 16) {
                        ForEach(viewModel.dramas(in: category.id)) { drama in
                            Button {
                                presentingDrama = drama
                            } label: {
                                TheaterDramaCard(drama: drama)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.bottom, 24)
                    .padding(.top, 8)
                }
                .tag(Optional(category.id))
            }
        }
        .tabViewStyle(.page(indexDisplayMode: .never))
    }
}

private struct TheaterDramaCard: View {
    let drama: Drama

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                if let posterURL = drama.posterURL {
                    AsyncImage(url: posterURL) { phase in
                        switch phase {
                        case .success(let image):
                            image.resizable().scaledToFill()
                        case .failure:
                            Color.gray.opacity(0.25)
                        case .empty:
                            ProgressView()
                        @unknown default:
                            Color.gray.opacity(0.25)
                        }
                    }
                } else {
                    Color.gray.opacity(0.25)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(3.0 / 4.0, contentMode: .fit)
            .clipShape(RoundedRectangle(cornerRadius: 10))

            Text(drama.title)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.primary)
                .lineLimit(2)

            Text("共\(max(drama.totalEpisodes, drama.episodes.count))集")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct SearchPlaceholderView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 14) {
                Image(systemName: "magnifyingglass.circle")
                    .font(.system(size: 42))
                    .foregroundStyle(.secondary)
                Text("搜索功能暂未实现")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .navigationTitle("搜索")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("关闭") {
                        dismiss()
                    }
                }
            }
        }
    }
}
