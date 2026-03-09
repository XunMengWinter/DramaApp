import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    Button {
                        // 登录逻辑按需求暂不实现
                    } label: {
                        HStack(spacing: 12) {
                            Image(systemName: "person.crop.circle.fill")
                                .font(.system(size: 28))
                                .foregroundStyle(Color.accentColor)
                            VStack(alignment: .leading, spacing: 4) {
                                Text("立即登录")
                                    .font(.headline)
                                    .foregroundStyle(.primary)
                                Text("登录后同步观看记录")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .foregroundStyle(.secondary)
                        }
                        .padding(14)
                        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                    }
                    .buttonStyle(.plain)

                    Text("播放历史")
                        .font(.title3.bold())

                    if playbackManager.historyItems.isEmpty {
                        Text("暂时没有播放历史")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    } else {
                        ForEach(playbackManager.historyItems) { item in
                            HistoryRow(item: item)
                        }
                    }
                }
                .padding(16)
            }
            .navigationTitle("我的")
        }
    }
}

private struct HistoryRow: View {
    let item: PlaybackManager.HistoryItem

    var body: some View {
        HStack(spacing: 12) {
            historyPoster

            VStack(alignment: .leading, spacing: 8) {
                Text(item.title)
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.primary)
                    .lineLimit(2)

                ProgressView(value: item.progressValue)
                    .progressViewStyle(.linear)

                Text(item.progressText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private var historyPoster: some View {
        if let posterURL = item.posterURL {
            AsyncImage(url: posterURL) { phase in
                switch phase {
                case .success(let image):
                    image
                        .resizable()
                        .scaledToFill()
                case .failure:
                    Color.gray.opacity(0.3)
                case .empty:
                    ProgressView()
                @unknown default:
                    Color.gray.opacity(0.3)
                }
            }
            .frame(width: 78, height: 104)
            .clipShape(RoundedRectangle(cornerRadius: 8))
        } else {
            Color.gray.opacity(0.3)
                .frame(width: 78, height: 104)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}
