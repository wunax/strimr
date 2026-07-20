import SwiftUI

struct EpisodeCardView: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let onSelect: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var regularImageWidth: CGFloat {
        UIScreen.main.bounds.width / 3
    }

    var body: some View {
        Button(action: onSelect) {
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

                        detailStack
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }

    private var detailStack: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(episode.tertiaryLabel.map { "\($0) - \(episode.title)" } ?? episode.title)
                .font(.title3)
                .fontWeight(.semibold)
                .lineLimit(1)

            if let summary = episode.summary, !summary.isEmpty {
                Text(summary)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .lineLimit(3)
            }
        }
    }
}
