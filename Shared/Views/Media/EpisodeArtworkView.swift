import SwiftUI

struct EpisodeArtworkView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let episode: MediaItem
    let artworkPath: String?
    let width: CGFloat
    let runtime: String?
    let progress: Double?
    private let aspectRatio: CGFloat = 16 / 9

    private var isSpoilerProtected: Bool {
        episode.isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            ArtworkPathView(
                path: artworkPath,
                width: Int(width),
                height: Int(width / aspectRatio),
            )
            .id(artworkPath)
            .frame(width: width, height: width / aspectRatio)
            .background(Color.black)

            if let runtime {
                Label {
                    Text(runtime)
                } icon: {
                    Image(systemName: "clock")
                }
                .font(.badge)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .glassSurface(in: Capsule())
                .padding(10)
            }
        }
        .overlay(alignment: .bottomLeading) {
            if let progress {
                CardProgressBar(progress: progress)
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
        .downloadStatusOverlay(.playable(episode))
        .overlay(alignment: .topLeading) {
            if isSpoilerProtected {
                SpoilerProtectionIndicator()
                    .padding(8)
            }
        }
    }
}
