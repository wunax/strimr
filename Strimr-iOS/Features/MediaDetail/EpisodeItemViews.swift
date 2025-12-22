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

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            EpisodeArtworkView(
                episode: episode,
                imageURL: imageURL,
                width: cardWidth,
                runtime: runtime,
                progress: progress
            )

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
        .padding(.vertical, 12)
        .frame(width: cardWidth)
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay?()
        }
    }
}
