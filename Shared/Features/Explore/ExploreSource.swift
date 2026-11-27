import Foundation

/// An external catalog shown in the Explore tab.
@MainActor
protocol ExploreSource: AnyObject {
    var id: ExploreSourceID { get }
    /// Fixed rails, in display order. The watchlist rail comes from `watchlist` and is not listed here.
    var rows: [ExploreRowID] { get }
    var watchlist: ExploreWatchlist? { get }
    var hasHubs: Bool { get }

    func fetchRow(_ row: ExploreRowID, page: Int) async throws -> ExplorePage
    /// Rails the source defines itself, shown after the fixed ones.
    func fetchHubs() async throws -> [ExploreHub]
    func fetchHub(id: String) async throws -> ExplorePage
    func search(_ query: String) async throws -> [ExploreItem]
    /// Fills what the rails leave out: external ids, summary, related titles.
    func detail(of item: ExploreItem) async throws -> ExploreDetail
    /// How this source's watchlist knows a server item, or nil when it cannot hold it.
    func watchlistTarget(kind: ExploreItemKind, externalIDs: ExternalIDs, plexGuidID: String?) async throws
        -> ExploreWatchlistTarget?
}

extension ExploreSource {
    var hasHubs: Bool {
        false
    }

    func fetchHubs() async throws -> [ExploreHub] {
        []
    }

    func fetchHub(id _: String) async throws -> ExplorePage {
        ExplorePage(items: [])
    }

    func detail(of item: ExploreItem) async throws -> ExploreDetail {
        ExploreDetail(item: item)
    }

    func watchlistTarget(kind _: ExploreItemKind, externalIDs _: ExternalIDs, plexGuidID _: String?) async throws
        -> ExploreWatchlistTarget?
    {
        nil
    }
}

extension ExploreSource {
    var displayName: String {
        id.displayName
    }
}
