import SwiftUI

struct EpisodeCardView: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let cardWidth: CGFloat?
    let isWatched: Bool
    let isUpdatingWatchStatus: Bool
    let onToggleWatch: (() -> Void)?
    let onPlay: (() -> Void)?
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var artworkWidth: CGFloat? {
        guard isRegularWidth else { return cardWidth }
        let preferredWidth: CGFloat = 240
        return min(cardWidth ?? preferredWidth, preferredWidth)
    }

    var body: some View {
        Group {
            if isRegularWidth {
                HStack(alignment: .top, spacing: 16) {
                    EpisodeArtworkView(
                        episode: episode,
                        imageURL: imageURL,
                        width: artworkWidth,
                        runtime: runtime,
                        progress: progress
                    )

                    detailStack
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    EpisodeArtworkView(
                        episode: episode,
                        imageURL: imageURL,
                        width: artworkWidth,
                        runtime: runtime,
                        progress: progress
                    )

                    detailStack
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .frame(width: cardWidth)
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
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
