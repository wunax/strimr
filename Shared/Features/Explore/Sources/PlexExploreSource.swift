import Foundation

/// plex.tv Discover, signed in as the profile's watchlist account.
@MainActor
final class PlexExploreSource: ExploreSource {
    let id = ExploreSourceID.plex
    let rows: [ExploreRowID] = []
    let hasHubs = true
    private(set) var watchlist: ExploreWatchlist?

    private static let hubLimit = 25
    private static let hubDetailLimit = 100
    private static let watchlistPageLimit = 40
    /// Directory hubs list browse categories, clip hubs trailers, and platform hubs streaming services.
    private static let skippedHubTypes: Set<String> = ["directory", "clip"]
    private static let skippedHubStyles: Set<String> = ["availabilityPlatforms"]

    private let repository: DiscoverWatchlistRepository
    private var hubKeys: [String: String] = [:]

    init(context: PlexAPIContext) throws {
        let repository = try DiscoverWatchlistRepository(context: context)
        self.repository = repository
        watchlist = ExploreWatchlist(
            fetch: { try await Self.loadWatchlist(repository: repository) },
            mutate: { add, target in
                guard let ratingKey = target.sourceID else { return }
                if add {
                    try await repository.addToWatchlist(ratingKey: ratingKey)
                } else {
                    try await repository.removeFromWatchlist(ratingKey: ratingKey)
                }
            },
        )
    }

    func fetchRow(_: ExploreRowID, page _: Int) async throws -> ExplorePage {
        ExplorePage(items: [])
    }

    /// A hub that fails is left out; the hubs only fail together when every one of them does.
    func fetchHubs() async throws -> [ExploreHub] {
        let candidates = try await repository.getHomeHubs().compactMap(Self.candidate)
        var keys: [String: String] = [:]
        var firstError: Error?
        let results = await withTaskGroup(of: (Int, Result<PlexDiscoverContainer, Error>).self) { group in
            for (index, candidate) in candidates.enumerated() {
                group.addTask { @MainActor [repository] in
                    do {
                        let container = try await repository.getHub(key: candidate.key, limit: Self.hubLimit + 1)
                        return (index, .success(container))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }
            var results: [Int: PlexDiscoverContainer] = [:]
            for await (index, result) in group {
                switch result {
                case let .success(container): results[index] = container
                case let .failure(error): firstError = firstError ?? error
                }
            }
            return results
        }
        if results.isEmpty, let firstError {
            throw firstError
        }
        var hubs: [ExploreHub] = []
        for (index, candidate) in candidates.enumerated() {
            guard let container = results[index] else { continue }
            let metadata = container.metadata.isEmpty ? container.hubs.first?.metadata ?? [] : container.metadata
            let items = metadata.compactMap(Self.item)
            guard !items.isEmpty else { continue }
            keys[candidate.id] = candidate.key
            hubs.append(ExploreHub(
                id: candidate.id,
                title: candidate.title,
                page: ExplorePage(
                    items: Array(items.prefix(Self.hubLimit)),
                    hasMore: items.count > Self.hubLimit || (container.totalSize ?? 0) > Self.hubLimit,
                ),
            ))
        }
        hubKeys = keys
        return hubs
    }

    /// Discover ignores offsets on hub keys, so a hub is a single page.
    func fetchHub(id: String) async throws -> ExplorePage {
        guard let key = hubKeys[id] else { return ExplorePage(items: []) }
        let container = try await repository.getHub(key: key, limit: Self.hubDetailLimit)
        let metadata = container.metadata.isEmpty ? container.hubs.first?.metadata ?? [] : container.metadata
        return ExplorePage(items: metadata.compactMap(Self.item))
    }

    func search(_ query: String) async throws -> [ExploreItem] {
        try await repository.search(query: query).compactMap(Self.item)
    }

    /// Rails carry no external ids, which only come with the title's own metadata.
    func detail(of item: ExploreItem) async throws -> ExploreDetail {
        async let metadata = repository.getMetadata(ratingKey: item.sourceID)
        async let related = repository.getRelated(ratingKey: item.sourceID)
        let enriched = try await metadata.flatMap(Self.item).map(item.enriched) ?? item
        let relatedItems = await (try? related)?.compactMap(Self.item) ?? []
        return ExploreDetail(item: enriched, related: relatedItems.filter { $0.id != item.id })
    }

    /// A Plex server's guid is the Discover rating key; other servers are matched on their external ids.
    func watchlistTarget(kind: ExploreItemKind, externalIDs: ExternalIDs, plexGuidID: String?) async throws
        -> ExploreWatchlistTarget?
    {
        if let plexGuidID {
            return ExploreWatchlistTarget(kind: kind, externalIDs: externalIDs, sourceID: plexGuidID)
        }
        let guid = externalIDs.imdb.map { "imdb://\($0)" }
            ?? externalIDs.tmdb.map { "tmdb://\($0)" }
            ?? externalIDs.tvdb.map { "tvdb://\($0)" }
        guard let guid,
              let metadata = try await repository.match(guid: guid, type: kind == .movie ? 1 : 2),
              let item = Self.item(from: metadata), item.kind == kind
        else { return nil }
        return ExploreWatchlistTarget(kind: kind, externalIDs: item.externalIDs, sourceID: item.sourceID)
    }

    private static func loadWatchlist(repository: DiscoverWatchlistRepository) async throws -> [ExploreItem] {
        var items: [ExploreItem] = []
        var start = 0
        for _ in 0 ..< watchlistPageLimit {
            let container = try await repository.getWatchlist(start: start)
            items += container.metadata.compactMap(item)
            start += container.metadata.count
            let total = container.totalSize ?? container.size ?? start
            if container.metadata.isEmpty || start >= total {
                break
            }
        }
        return items
    }

    private static func candidate(_ hub: PlexDiscoverHub) -> (id: String, key: String, title: String)? {
        if let type = hub.type, skippedHubTypes.contains(type) {
            return nil
        }
        if let style = hub.style, skippedHubStyles.contains(style) {
            return nil
        }
        guard let key = hub.key ?? hub.hubKey, !key.isEmpty, let title = hub.title, !title.isEmpty else { return nil }
        return (hub.hubIdentifier ?? key, key, title)
    }

    static func item(from metadata: PlexDiscoverMetadata) -> ExploreItem? {
        let kind: ExploreItemKind
        switch metadata.type {
        case "movie": kind = .movie
        case "show": kind = .show
        default: return nil
        }
        guard let ratingKey = metadata.ratingKey, !ratingKey.isEmpty, let title = metadata.title, !title.isEmpty
        else { return nil }
        var guids = metadata.guids.map(\.id)
        if let guid = metadata.guid {
            guids.append(guid)
        }
        let plexGuid = metadata.guid?.hasPrefix("plex://") == true
            ? metadata.guid
            : "plex://\(kind == .movie ? "movie" : "show")/\(ratingKey)"
        return ExploreItem(
            source: .plex,
            sourceID: ratingKey,
            kind: kind,
            title: title,
            originalTitle: metadata.originalTitle,
            year: metadata.year,
            overview: metadata.summary,
            posterURL: metadata.thumb.flatMap(URL.init(string:)),
            backdropURL: metadata.art.flatMap(URL.init(string:)),
            externalIDs: ExternalIDs(plexGuids: guids),
            plexGuid: plexGuid,
        )
    }
}
