import SwiftUI

struct EpisodeCardView: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let isWatched: Bool
    let isUpdatingWatchStatus: Bool
    let onToggleWatch: (() -> Void)?
    let onPlay: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }
    
    private var regularImageWidth: CGFloat {
        UIScreen.main.bounds.width / 3
    }

    var body: some View {
        Group {
            if isRegularWidth {
                HStack(alignment: .top, spacing: 16) {
                    EpisodeArtworkView(
                        episode: episode,
                        imageURL: imageURL,
                        width: regularImageWidth,
                        runtime: runtime,
                        progress: progress,
                    )
                    .overlay { playOverlay }

                    detailStack
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    GeometryReader { proxy in
                        EpisodeArtworkView(
                            episode: episode,
                            imageURL: imageURL,
                            width: proxy.size.width,
                            runtime: runtime,
                            progress: progress,
                        )
                    }
                    .aspectRatio(16 / 9, contentMode: .fit)
                    .frame(maxWidth: .infinity)
                    .overlay { playOverlay }

                    detailStack
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay?()
        }
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .center, spacing: 8) {
                if let index = episode.index {
                    Text("media.detail.episodeNumber \(index)")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let onToggleWatch {
                    Button {
                        onToggleWatch()
                    } label: {
                        Group {
                            if isUpdatingWatchStatus {
                                ProgressView()
                                    .scaleEffect(0.8, anchor: .center)
                            } else {
                                Image(systemName: isWatched ? "checkmark.circle.fill" : "checkmark.circle")
                                    .font(.headline.weight(.semibold))
                            }
                        }
                        .frame(width: 22, height: 22)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(.brandSecondary)
                }
            }

            Text(episode.title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(2)

            if let summary = episode.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }

    private var playOverlay: some View {
        Image(systemName: "play.fill")
            .font(.title2.weight(.semibold))
            .foregroundStyle(.white)
            .padding(12)
            .background(Color.black.opacity(0.50), in: Circle())
    }
}
