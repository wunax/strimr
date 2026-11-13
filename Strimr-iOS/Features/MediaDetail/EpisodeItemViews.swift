import SwiftUI

struct EpisodeCardView: View {
    let episode: MediaItem
    let artworkPath: String?
    let runtime: String?
    let progress: Double?
    let onSelect: () -> Void
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isRegularWidth: Bool {
        horizontalSizeClass == .regular
    }

    var body: some View {
        Button(action: onSelect) {
            Group {
                if isRegularWidth {
                    EpisodeRowLayout {
                        GeometryReader { proxy in
                            EpisodeArtworkView(
                                episode: episode,
                                artworkPath: artworkPath,
                                width: proxy.size.width,
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
                                artworkPath: artworkPath,
                                width: proxy.size.width,
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
        .dimmedWhenUnavailableOffline(episode)
    }

    private var detailStack: some View {
        EpisodeRowText(episode: episode, runtime: runtime)
    }
}
