import Foundation

@MainActor
final class PlexFavoritesService: MediaFavoritesService {
    let supportsFavorites = true

    private let context: PlexAPIContext
    private let store: FavoritesStore
    private let scope: FavoriteScope
    private let server: ServerIdentity

    init(
        context: PlexAPIContext,
        store: FavoritesStore,
        scope: FavoriteScope,
    ) {
        self.context = context
        self.store = store
        self.scope = scope
        server = ServerIdentity(provider: .plex, id: scope.serverID)
    }

    func favorites() async throws -> [MediaItem] {
        store.favorites(for: scope).map { $0.media(serverID: scope.serverID) }
    }

    func isFavorite(_ media: MediaItem) async throws -> Bool {
        store.contains(mediaID: media.id, in: scope)
    }

    func setFavorite(_ favorite: Bool, media: MediaItem) async throws {
        if favorite {
            let response = try await MetadataRepository(context: context).getMetadata(ratingKey: media.id)
            guard let item = response.mediaContainer.metadata?.first else {
                throw PlexAPIError.invalidResponse
            }
            store.setFavorite(
                true,
                snapshot: PlexFavoriteSnapshot(plexItem: item, server: server),
                in: scope,
            )
        } else {
            store.setFavorite(
                false,
                snapshot: PlexFavoriteSnapshot(media: media, libraryID: nil, libraryTitle: nil),
                in: scope,
            )
        }
    }
}
