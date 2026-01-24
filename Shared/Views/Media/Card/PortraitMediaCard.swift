import SwiftUI

struct PortraitMediaCard: View {
    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private let aspectRatio: CGFloat = 2 / 3

    init(
        media: MediaDisplayItem,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void,
    ) {
        self.media = media
        self.height = height
        self.width = width
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
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        MediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: .thumb,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
