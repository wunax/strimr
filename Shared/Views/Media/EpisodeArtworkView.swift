import SwiftUI

struct EpisodeArtworkView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let episode: MediaItem
    let imageURL: URL?
    let width: CGFloat
    let runtime: String?
    let progress: Double?
    private let aspectRatio: CGFloat = 16 / 9

    private var isSpoilerProtected: Bool {
        episode.isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            Group {
                if let imageURL {
                    AsyncImage(url: imageURL) { phase in
                        if let image = phase.image {
                            image.resizable().scaledToFit()
                        } else {
                            Color.gray.opacity(0.15)
                        }
                    }
                } else {
                    ArtworkPathView(
                        path: episode.thumbPath ?? episode.parentThumbPath ?? episode.grandparentThumbPath,
                        width: Int(width),
                        height: Int(width / aspectRatio),
                    )
                }
            }
            .frame(width: width)
            .aspectRatio(aspectRatio, contentMode: .fit)
            .background(Color.black)

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
        .mediaArtworkStyle(.compact, borderColor: .white.opacity(0.05))
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: .playable(episode))
        }
        .overlay(alignment: .topLeading) {
            if isSpoilerProtected {
                SpoilerProtectionIndicator()
                    .padding(8)
            }
        }
    }
}
