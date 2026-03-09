import SwiftUI

struct ProfileTabView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager
    @State private var showClearCacheAlert = false

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

                    Text("缓存管理")
                        .font(.title3.bold())

                    VStack(spacing: 12) {
                        CacheInfoRow(title: "缓存占用", value: formatBytes(playbackManager.cacheStatus.usedBytes))
                        CacheInfoRow(title: "缓存文件", value: "\(playbackManager.cacheStatus.fileCount) 个")
                        CacheInfoRow(title: "容量上限", value: formatBytes(playbackManager.cacheStatus.limitBytes))

                        HStack(spacing: 10) {
                        

                            Button(role: .destructive) {
                                showClearCacheAlert = true
                            } label: {
                                if playbackManager.isClearingCache {
                                    ProgressView()
                                        .frame(maxWidth: .infinity)
                                } else {
                                    Label("清理缓存", systemImage: "trash")
                                        .frame(maxWidth: .infinity)
                                }
                            }
                            .buttonStyle(.borderedProminent)
                            .disabled(playbackManager.isClearingCache || playbackManager.cacheStatus.fileCount == 0)
                        }
                    }
                    .padding(12)
                    .background(Color(.secondarySystemBackground), in: RoundedRectangle(cornerRadius: 12))
                }
                .padding(16)
            }
            .navigationTitle("我的")
            .task {
                await playbackManager.refreshVideoCacheStatus()
            }
            .refreshable {
                await playbackManager.refreshVideoCacheStatus()
            }
            .alert("确认清理视频缓存？", isPresented: $showClearCacheAlert) {
                Button("取消", role: .cancel) {}
                Button("清理", role: .destructive) {
                    Task {
                        await playbackManager.clearVideoCache()
                    }
                }
            } message: {
                Text("已缓存的视频文件将被删除，不影响播放记录。")
            }
        }
    }

    private func formatBytes(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        return formatter.string(fromByteCount: bytes)
    }
}

private struct CacheInfoRow: View {
    let title: String
    let value: String

    var body: some View {
        HStack {
            Text(title)
                .font(.subheadline)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundStyle(.primary)
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
