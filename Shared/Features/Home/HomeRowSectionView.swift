import SwiftUI

struct HomeRowSectionView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.mediaCardActions) private var mediaCardActions
    @Environment(ServerRegistry.self) private var registry
    let row: HomeRow
    let showsLabels: Bool
    let onViewAll: (Hub) -> Void
    let onSelectMedia: (MediaDisplayItem) -> Void
    @State private var copyChoice: CopyChoice?

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
            .environment(\.mediaCardIsInContinueWatching, row.kind == .continueWatching)
        }
        .taskPresentation(item: $copyChoice, style: .contextual) { choice in
            MediaSourceSelectionView(title: "media.copySelection.title", sources: choice.sources) { source in
                if let item = source.media.playableItem {
                    mediaCardActions?.play(item, false)
                }
            }
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
            if let copies = row.copies[item.identity], copies.count > 1 {
                copyChoice = CopyChoice(sources: sources(for: copies))
            } else {
                mediaCardActions.play(item, false)
            }
        } else {
            onSelectMedia(media)
        }
    }

    private func sources(for copies: [MediaItem]) -> [SearchResultSource] {
        MediaCopy.sorted(copies.map { item in
            MediaCopy(
                media: item,
                serverName: registry.serverName(for: item.identity.server) ?? item.identity.server.id,
                isReachable: true,
            )
        })
        .map { SearchResultSource(server: $0.server, serverName: $0.serverName, media: .playable($0.media)) }
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

private struct CopyChoice: Identifiable {
    let id = UUID()
    let sources: [SearchResultSource]
}
