import Foundation

extension Hub {
    @MainActor
    init(plexHub: PlexHub) {
        self.init(
            id: plexHub.hubIdentifier,
            key: plexHub.key,
            hubKey: plexHub.hubKey,
            title: plexHub.title,
            size: plexHub.size,
            more: plexHub.more,
            items: (plexHub.metadata ?? [])
                .filter(\.type.isSupported)
                .compactMap(MediaDisplayItem.init),
        )
    }
}
