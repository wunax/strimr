import SwiftUI

struct EpisodeCardView: View {
    let episode: MediaItem
    let imageURL: URL?
    let runtime: String?
    let progress: Double?
    let onSelect: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @State private var rowWidth: CGFloat = 0

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    private var regularImageWidth: CGFloat {
        rowWidth / 3
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if isRegularWidth {
                    HStack(alignment: .top, spacing: 16) {
                        // The artwork width also sizes the image request, so wait for the row to be measured.
                        if rowWidth > 0 {
                            EpisodeArtworkView(
                                episode: episode,
                                imageURL: imageURL,
                                width: regularImageWidth,
                                runtime: nil,
                                progress: progress,
                            )
                        }
                        detailStack
                    }
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        GeometryReader { proxy in
                            EpisodeArtworkView(
                                episode: episode,
                                imageURL: imageURL,
                                width: proxy.size.width,
                                runtime: nil,
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { rowWidth = $0 }
            .padding(.vertical, 12)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .dimmedWhenUnavailableOffline(episode)
    }

    private var detailStack: some View {
        EpisodeRowText(episode: episode, runtime: runtime)
    }
}
