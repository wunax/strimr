import Foundation

@MainActor
final class JellyfinFavoritesService: MediaFavoritesService {
    let supportsFavorites = true

    private let catalog: JellyfinCatalogService
    private let server: ServerIdentity

    init(context: JellyfinAPIContext, server: ServerIdentity) {
        catalog = JellyfinCatalogService(context: context)
        self.server = server
    }

    func favorites() async throws -> [MediaItem] {
        try await catalog.favoriteItems().map { MediaItem(jellyfinItem: $0, server: server) }
    }

    func isFavorite(_ media: MediaItem) async throws -> Bool {
        try await catalog.isFavorite(itemID: media.id)
    }

    func setFavorite(_ favorite: Bool, media: MediaItem) async throws {
        try await catalog.setFavorite(favorite, itemID: media.id)
    }
}
