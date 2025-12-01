import Foundation

extension Hub {
    @MainActor
    init(plexHub: PlexHub) {
        self.init(
            id: plexHub.hubIdentifier,
            title: plexHub.title,
            items: (plexHub.metadata ?? []).map(MediaItem.init)
        )
    }
}
