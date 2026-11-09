import SwiftUI

struct EpisodeArtworkView: View {
    @Environment(SettingsManager.self) private var settingsManager
    let episode: MediaItem
    let artworkPath: String?
    let width: CGFloat
    let progress: Double?
    var leadingBadge: LocalizedStringKey?
    private let aspectRatio: CGFloat = 16 / 9

    private var isSpoilerProtected: Bool {
        episode.isSpoilerProtected(at: settingsManager.interface.spoilerProtection)
    }

    var body: some View {
        ArtworkPathView(
            path: artworkPath,
            width: Int(width),
            height: Int(width / aspectRatio),
        )
        .id(artworkPath)
        .frame(width: width, height: width / aspectRatio)
        .background(Color.black)
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
            if isSpoilerProtected || leadingBadge != nil {
                HStack(spacing: 8) {
                    if isSpoilerProtected {
                        SpoilerProtectionIndicator()
                    }
                    if let leadingBadge {
                        Text(leadingBadge)
                            .font(.badge)
                            .textCase(.uppercase)
                            .foregroundStyle(.textPrimary)
                            .padding(.horizontal, 10)
                            .padding(.vertical, 4)
                            .background(.badgeBackground, in: Capsule(style: .continuous))
                    }
                }
                .padding(8)
            }
        }
    }
}
