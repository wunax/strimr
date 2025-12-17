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
#if os(macOS)
    @State private var isHovering = false
#endif

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
#if os(tvOS) || os(macOS)
        .padding(12)
#else
        .padding(.vertical, 12)
#endif
        .frame(width: cardWidth)
#if os(tvOS)
        .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 18))
        .focusable(true)
        .shadow(color: .black.opacity(0.2), radius: 10, y: 6)
#elseif os(macOS)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.primary.opacity(0.05))
        )
        .shadow(color: .black.opacity(isHovering ? 0.12 : 0.06), radius: isHovering ? 8 : 5, y: isHovering ? 4 : 2)
        .onHover { isHovering = $0 }
#else
        // iOS: leave flat, image/overlays carry hierarchy
#endif
        .contentShape(Rectangle())
        .onTapGesture {
            onPlay?()
        }
    }
}

struct EpisodeArtworkView: View {
    let episode: MediaItem
    let imageURL: URL?
    let width: CGFloat?
    let runtime: String?
    let progress: Double?
    private let aspectRatio: CGFloat = 16 / 9

    var body: some View {
        ZStack(alignment: .topLeading) {
            AsyncImage(url: imageURL) { phase in
                switch phase {
                case let .success(image):
                    image
                        .resizable()
                        .scaledToFill()
                case .empty:
                    Color.gray.opacity(0.15)
                case .failure:
                    Color.gray.opacity(0.15)
                @unknown default:
                    Color.gray.opacity(0.15)
                }
            }
            .frame(maxWidth: .infinity)
            .aspectRatio(aspectRatio, contentMode: .fit)

            if let runtime {
                Label {
                    Text(runtime)
                        .font(.caption2)
                        .fontWeight(.semibold)
                } icon: {
                    Image(systemName: "clock")
                        .font(.caption2)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(.ultraThinMaterial, in: Capsule())
                .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
        .frame(width: width)
        .clipped()
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay {
            RoundedRectangle(cornerRadius: 12)
                .strokeBorder(.white.opacity(0.05))
        }
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: episode)
        }
    }
}
