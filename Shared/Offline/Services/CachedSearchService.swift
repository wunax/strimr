import Foundation

/// Online search is unchanged; offline, titles of cached items are matched locally (case and diacritics folded).
@MainActor
final class CachedSearchService: MediaSearchService {
    private let base: any MediaSearchService
    private let policy: OfflineCachePolicy

    init(base: any MediaSearchService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    func search(query: String, kinds: Set<MediaKind>) async throws -> [MediaDisplayItem] {
        try await policy.read(
            network: { try await base.search(query: query, kinds: kinds) },
            write: { _ in },
            fallback: {
                policy.store.search(query: query, owner: policy.owner)
                    .filter { kinds.isEmpty || kinds.contains($0.kind) }
                    .map(MediaDisplayItem.playable)
            },
        )
    }
}

/// Favorites are not available offline: reads and writes require the server.
@MainActor
final class CachedFavoritesService: MediaFavoritesService {
    private let base: any MediaFavoritesService
    private let policy: OfflineCachePolicy

    init(base: any MediaFavoritesService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    var supportsFavorites: Bool {
        base.supportsFavorites
    }

    func favorites() async throws -> [MediaItem] {
        try await policy.online { try await base.favorites() }
    }

    func isFavorite(_ media: MediaItem) async throws -> Bool {
        try await policy.online { try await base.isFavorite(media) }
    }

    func setFavorite(_ favorite: Bool, media: MediaItem) async throws {
        try await policy.online { try await base.setFavorite(favorite, media: media) }
    }
}
