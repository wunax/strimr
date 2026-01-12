import SwiftUI

struct PortraitMediaCard: View {
    let media: MediaItem
    let showsLabels: Bool
    let onTap: () -> Void

    var body: some View {
        MediaCard(
            layout: .portrait,
            media: media,
            artworkKind: .thumb,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
