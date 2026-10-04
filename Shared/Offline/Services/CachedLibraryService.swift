import Foundation

private struct HubSnapshot: Codable {
    let hub: Hub
    let itemIDs: [String]
}

@MainActor
class CachedLibraryService: MediaLibraryService {
    let base: any MediaLibraryService
    let policy: OfflineCachePolicy

    init(base: any MediaLibraryService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    func libraries() async throws -> [Library] {
        try await policy.read(
            network: { try await base.libraries() },
            write: { policy.store.store(libraries: $0, owner: policy.owner) },
            fallback: {
                let libraries = policy.store.libraries(owner: policy.owner)
                return libraries.isEmpty ? nil : libraries
            },
        )
    }

    func randomArtwork(for library: Library) async throws -> ArtworkResource? {
        let key = "library-artwork:\(library.id)|720"
        return try await policy.read(
            network: {
                guard let resource = try await base.randomArtwork(for: library) else { return nil }
                switch resource {
                case .data:
                    return resource
                case let .url(url):
                    return try await .data(URLSession.shared.data(from: url).0)
                }
            },
            write: { resource in
                guard case let .data(data)? = resource else { return }
                policy.store.storeArtwork(data, key: key, owner: policy.owner, width: nil, height: nil, pinned: false)
            },
            fallback: {
                guard let url = policy.store.artworkFileURL(key: key, owner: policy.owner),
                      let data = try? Data(contentsOf: url)
                else { return nil }
                return .data(data)
            },
        )
    }

    func recommended(in library: Library) async throws -> [Hub] {
        let key = "recommended:\(library.id)"
        return try await policy.read(
            network: { try await base.recommended(in: library) },
            write: { hubs in
                let snapshots = hubs.map { HubSnapshot(hub: Self.emptied($0), itemIDs: $0.items.map(\.id)) }
                policy.store.store(
                    list: hubs.flatMap(\.items),
                    key: key,
                    payload: policy.store.encode(snapshots),
                    owner: policy.owner,
                )
            },
            fallback: { cachedHubs(key: key) },
        )
    }

    func items(
        in library: Library,
        parentID: String?,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        try await policy.read(
            network: { try await base.items(in: library, parentID: parentID, startIndex: startIndex, limit: limit) },
            write: { page in policy.store.store(displayItems: page.items, owner: policy.owner, libraryID: library.id) },
            fallback: { offlinePage(library: library, startIndex: startIndex) },
        )
    }

    func collections(in library: Library) async throws -> [CollectionMediaItem] {
        let key = "collections:\(library.id)"
        return try await policy.read(
            network: { try await base.collections(in: library) },
            write: { policy.store.store(list: $0.map(MediaDisplayItem.collection), key: key, owner: policy.owner) },
            fallback: {
                policy.store.list(key: key, owner: policy.owner)?.items.compactMap { item in
                    guard case let .collection(collection) = item else { return nil }
                    return collection
                }
            },
        )
    }

    func playlists(in library: Library) async throws -> [PlaylistMediaItem] {
        let key = "playlists:\(library.id)"
        return try await policy.read(
            network: { try await base.playlists(in: library) },
            write: { policy.store.store(list: $0.map(MediaDisplayItem.playlist), key: key, owner: policy.owner) },
            fallback: {
                policy.store.list(key: key, owner: policy.owner)?.items.compactMap { item in
                    guard case let .playlist(playlist) = item else { return nil }
                    return playlist
                }
            },
        )
    }

    /// Offline library content: every cached movie or series of the library, sorted by title, in a single page.
    func offlinePage(library: Library, startIndex: Int) -> MediaPage<MediaDisplayItem> {
        let items = policy.store.libraryItems(libraryID: library.id, owner: policy.owner)
        return MediaPage(items: startIndex == 0 ? items : [], startIndex: startIndex, totalCount: items.count)
    }

    func cachedHubs(key: String) -> [Hub]? {
        guard let snapshot = policy.store.list(key: key, owner: policy.owner),
              let hubs = snapshot.payload.flatMap({ policy.store.decode([HubSnapshot].self, from: $0) })
        else { return nil }
        let itemsByID = Dictionary(snapshot.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return hubs.compactMap { entry in
            let items = entry.itemIDs.compactMap { itemsByID[$0] }
            guard !items.isEmpty else { return nil }
            return Hub(
                id: entry.hub.id,
                key: entry.hub.key,
                hubKey: entry.hub.hubKey,
                title: entry.hub.title,
                size: entry.hub.size,
                more: entry.hub.more,
                items: items,
                server: policy.owner.server,
            )
        }
    }

    static func emptied(_ hub: Hub) -> Hub {
        Hub(
            id: hub.id,
            key: hub.key,
            hubKey: hub.hubKey,
            title: hub.title,
            size: hub.size,
            more: hub.more,
            items: [],
            server: hub.server,
        )
    }
}

@MainActor
final class CachedPlexLibraryService: CachedLibraryService, PlexAdvancedLibraryService {
    private let advanced: any PlexAdvancedLibraryService

    init(base: any MediaLibraryService & PlexAdvancedLibraryService, policy: OfflineCachePolicy) {
        advanced = base
        super.init(base: base, policy: policy)
    }

    func advancedBrowse(
        path: String,
        queryItems: [URLQueryItem],
        startIndex: Int,
        limit: Int,
    ) async throws -> PlexAdvancedBrowsePage {
        let libraryID = Self.sectionID(in: path)
        return try await policy.read(
            network: {
                try await advanced.advancedBrowse(
                    path: path,
                    queryItems: queryItems,
                    startIndex: startIndex,
                    limit: limit,
                )
            },
            write: { page in
                let items = page.items.compactMap { item -> MediaDisplayItem? in
                    guard case let .media(media) = item else { return nil }
                    return media
                }
                policy.store.store(displayItems: items, owner: policy.owner, libraryID: libraryID)
            },
            fallback: {
                guard let libraryID else { return nil }
                let page = offlinePage(
                    library: Library(id: libraryID, title: "", type: .unknown, server: policy.owner.server),
                    startIndex: startIndex,
                )
                return PlexAdvancedBrowsePage(
                    items: page.items.map(LibraryBrowseItem.media),
                    totalCount: page.totalCount ?? page.items.count,
                    meta: nil,
                )
            },
        )
    }

    func filterOptions(path: String, queryItems: [URLQueryItem]) async throws -> [PlexFilterDirectory] {
        try await policy.online { try await advanced.filterOptions(path: path, queryItems: queryItems) }
    }

    func sectionCharacters(path: String, queryItems: [URLQueryItem]) async throws -> [PlexAdvancedSectionCharacter] {
        try await policy.online { try await advanced.sectionCharacters(path: path, queryItems: queryItems) }
    }

    func collectionCharacters(sectionID: Int) async throws -> [PlexAdvancedSectionCharacter] {
        try await policy.online { try await advanced.collectionCharacters(sectionID: sectionID) }
    }

    func collectionPage(sectionID: Int, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        let key = "collections:\(sectionID)"
        return try await policy.read(
            network: { try await advanced.collectionPage(sectionID: sectionID, startIndex: startIndex, limit: limit) },
            write: { page in
                guard startIndex == 0 else {
                    policy.store.store(displayItems: page.items, owner: policy.owner)
                    return
                }
                policy.store.store(list: page.items, key: key, owner: policy.owner)
            },
            fallback: {
                guard let items = policy.store.list(key: key, owner: policy.owner)?.items else { return nil }
                return MediaPage(items: startIndex == 0 ? items : [], startIndex: startIndex, totalCount: items.count)
            },
        )
    }

    private static func sectionID(in path: String) -> String? {
        let components = path.split(separator: "/")
        guard let index = components.firstIndex(of: "sections"), components.indices.contains(index + 1) else {
            return nil
        }
        return String(components[index + 1])
    }
}

@MainActor
final class CachedJellyfinLibraryService: CachedLibraryService, AdvancedLibraryBrowseService {
    private let browse: any AdvancedLibraryBrowseService

    init(base: any MediaLibraryService & AdvancedLibraryBrowseService, policy: OfflineCachePolicy) {
        browse = base
        super.init(base: base, policy: policy)
    }

    func browseItems(
        in library: Library,
        parentID: String?,
        query: LibraryBrowseQuery,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        try await policy.read(
            network: {
                try await browse.browseItems(
                    in: library,
                    parentID: parentID,
                    query: query,
                    startIndex: startIndex,
                    limit: limit,
                )
            },
            write: { page in policy.store.store(displayItems: page.items, owner: policy.owner, libraryID: library.id) },
            fallback: { offlinePage(library: library, startIndex: startIndex) },
        )
    }

    func browseFilterOptions(in library: Library) async throws -> LibraryBrowseFilterOptions {
        try await policy.online { try await browse.browseFilterOptions(in: library) }
    }
}
