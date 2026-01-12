import SwiftUI

struct LandscapeMediaCard: View {
    let media: MediaItem
    let showsLabels: Bool
    let onTap: () -> Void

    var body: some View {
        MediaCard(
            layout: .landscape,
            media: media,
            artworkKind: .art,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
