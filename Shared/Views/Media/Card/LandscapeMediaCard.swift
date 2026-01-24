import SwiftUI

struct LandscapeMediaCard: View {
    let media: MediaDisplayItem
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass

    private let aspectRatio: CGFloat = 16 / 9

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
            90
        } else {
            124
        }
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)
        MediaCard(
            size: CGSize(width: resolvedWidth, height: resolvedHeight),
            media: media,
            artworkKind: .art,
            showsLabels: showsLabels,
            onTap: onTap,
        )
    }
}
