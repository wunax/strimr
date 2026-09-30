import Foundation

/// Online search is unchanged; offline, titles of cached items are matched locally (case and diacritics folded).
@MainActor
final class CachedSearchService: MediaSearchService {
    private let base: any MediaSearchService
    private let policy: OfflineCachePolicy
    private let serverName: String
    weak var services: MediaServices?

    init(base: any MediaSearchService, policy: OfflineCachePolicy, serverName: String) {
        self.base = base
        self.policy = policy
        self.serverName = serverName
    }

    func search(
        query: String,
        kinds: Set<MediaKind>,
        searchesAllServers: Bool,
    ) async throws -> [MediaSearchSource] {
        try await policy.read(
            network: { try await base.search(query: query, kinds: kinds, searchesAllServers: searchesAllServers) },
            write: { _ in },
            fallback: { localResults(query: query, kinds: kinds) },
        )
    }

    private func localResults(query: String, kinds: Set<MediaKind>) -> [MediaSearchSource]? {
        guard let services else { return nil }
        return policy.store.search(query: query, owner: policy.owner)
            .filter { kinds.isEmpty || kinds.contains($0.kind) }
            .map { item in
                MediaSearchSource(
                    serverIdentifier: policy.owner.server.id,
                    serverName: serverName,
                    media: .playable(item),
                    services: services,
                )
            }
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
