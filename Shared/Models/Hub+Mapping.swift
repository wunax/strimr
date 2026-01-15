import Foundation

extension Hub {
    @MainActor
    init(plexHub: PlexHub) {
        self.init(
            id: plexHub.hubIdentifier,
            title: plexHub.title,
            items: (plexHub.metadata ?? [])
                .filter { $0.type.isSupported }
                .map(MediaItem.init),
        )
    }
}
