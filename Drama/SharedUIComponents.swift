import AVKit
import SwiftUI

struct DramaPosterView: View {
    let drama: Drama
    let aspectRatio: Double

    var body: some View {
        ZStack {
            if let url = drama.posterURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case .success(let image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .failure:
                        posterFallback
                    case .empty:
                        ProgressView()
                            .tint(.white)
                    @unknown default:
                        posterFallback
                    }
                }
            } else {
                posterFallback
            }
        }
        .frame(maxWidth: .infinity)
        .aspectRatio(aspectRatio, contentMode: .fit)
        .background(Color.black)
        .clipped()
    }

    private var posterFallback: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color.gray.opacity(0.5)],
                startPoint: .top,
                endPoint: .bottom
            )
            Text(drama.title)
                .font(.headline)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 20)
        }
    }
}

struct SharedVideoPlayerView: View {
    @EnvironmentObject private var playbackManager: PlaybackManager

    var body: some View {
        VideoPlayer(player: playbackManager.player)
            .background(Color.black)
    }
}

struct LoadingFillView: View {
    let title: String

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 12) {
                ProgressView()
                    .tint(.white)
                Text(title)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.85))
            }
        }
    }
}

struct ErrorFillView: View {
    let message: String
    let retryAction: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            VStack(spacing: 14) {
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.92))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 20)
                Button("重试", action: retryAction)
                    .buttonStyle(.borderedProminent)
            }
        }
    }
}

struct DramaTagRow: View {
    let tags: [String]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(tags, id: \.self) { tag in
                    Text(tag)
                        .font(.caption)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.2), in: Capsule())
                }
            }
        }
        .scrollDisabled(true)
    }
}
