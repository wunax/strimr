import SwiftUI

struct HomeRowSectionView: View {
    let row: HomeRow
    let showsLabels: Bool
    let onViewAll: (Hub) -> Void
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        MediaHubSection(
            title: row.title,
            onViewAll: canOpenViewAll ? { onViewAll(row.hub) } : nil,
        ) {
            MediaCarousel(
                layout: row.style == .landscape ? .landscape : .portrait,
                items: row.items,
                showsLabels: showsLabels,
                onViewAll: carouselViewAllAction,
                onSelectMedia: onSelectMedia,
            )
        }
    }

    private var canOpenViewAll: Bool {
        #if os(tvOS)
            row.hub.canShowViewAll
        #else
            row.hub.canOpenDetail
        #endif
    }

    private var carouselViewAllAction: (() -> Void)? {
        #if os(tvOS)
            canOpenViewAll ? { onViewAll(row.hub) } : nil
        #else
            nil
        #endif
    }
}
