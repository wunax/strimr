import SwiftUI

struct HomeRowSectionView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.mediaCardActions) private var mediaCardActions
    let row: HomeRow
    let showsLabels: Bool
    let onViewAll: (Hub) -> Void
    let onSelectMedia: (MediaDisplayItem) -> Void

    var body: some View {
        MediaHubSection(
            title: row.title,
            subtitle: row.serverName,
            onViewAll: canOpenViewAll ? { onViewAll(row.hub) } : nil,
        ) {
            MediaCarousel(
                layout: row.style == .landscape ? .landscape : .portrait,
                items: row.items,
                showsLabels: showsLabels,
                onViewAll: carouselViewAllAction,
                onSelectMedia: select,
            )
            .environment(\.mediaCardOffersDetails, playsOnSelect)
        }
    }

    private var playsOnSelect: Bool {
        row.kind == .continueWatching && settingsManager.interface.continueWatchingAction == .play
    }

    private func select(_ media: MediaDisplayItem) {
        if playsOnSelect,
           let item = media.playableItem,
           let mediaCardActions
        {
            mediaCardActions.play(item, false)
        } else {
            onSelectMedia(media)
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
