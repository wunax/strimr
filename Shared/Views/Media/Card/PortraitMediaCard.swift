import SwiftUI

struct PortraitMediaCard: View {
    let media: MediaItem
    let height: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private let aspectRatio: CGFloat = 2 / 3

    init(
        media: MediaItem,
        height: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void
    ) {
        self.media = media
        self.height = height
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        if sizeClass == .compact {
            180
        } else {
            240
        }
    }

    var body: some View {
        let resolvedHeight = height ?? defaultHeight
        let width = resolvedHeight * aspectRatio
        MediaCard(
            size: CGSize(width: width, height: resolvedHeight),
            media: media,
            artworkKind: .thumb,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
