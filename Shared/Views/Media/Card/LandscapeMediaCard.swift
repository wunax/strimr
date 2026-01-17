import SwiftUI

struct LandscapeMediaCard: View {
    let media: MediaItem
    let height: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private let aspectRatio: CGFloat = 16 / 9

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
            90
        } else {
            124
        }
    }

    var body: some View {
        let resolvedHeight = height ?? defaultHeight
        let width = resolvedHeight * aspectRatio
        MediaCard(
            size: CGSize(width: width, height: resolvedHeight),
            media: media,
            artworkKind: .art,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
