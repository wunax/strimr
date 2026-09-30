import Foundation

private struct HomeRowSnapshot: Codable {
    let id: String
    let kind: String
    let style: String
    let hub: Hub
    let itemIDs: [String]
}

@MainActor
final class CachedHomeService: MediaHomeService {
    private static let homeKey = "home"
    private static let offlineDownloadsRowSuffix = ":offlineDownloads"

    static func isOfflineDownloadsRow(_ row: HomeRow) -> Bool {
        row.id.hasSuffix(offlineDownloadsRowSuffix)
    }

    private let base: any MediaHomeService
    private let policy: OfflineCachePolicy

    init(base: any MediaHomeService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    func loadHome(hiddenLibraryIDs: Set<String>, includesPlaylists: Bool) async throws -> HomeContent {
        let content = try await policy.read(
            network: {
                try await base.loadHome(hiddenLibraryIDs: hiddenLibraryIDs, includesPlaylists: includesPlaylists)
            },
            write: save,
            fallback: offlineHome,
        )
        guard !policy.isUnreachable else { return content }
        return HomeContent(rows: content.rows.map { row in
            HomeRow(
                id: row.id,
                kind: row.kind,
                style: row.style,
                hub: hub(row.hub, items: policy.overlayLocalProgress(row.hub.items)),
            )
        })
    }

    /// Last home snapshot, shown immediately while the network response is loading.
    func cachedHome() -> HomeContent? {
        guard let snapshot = policy.store.list(key: Self.homeKey, owner: policy.owner),
              let rows = snapshot.payload.flatMap({ policy.store.decode([HomeRowSnapshot].self, from: $0) })
        else { return nil }
        let itemsByID = Dictionary(snapshot.items.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return HomeContent(rows: rows.compactMap { row in
            guard let kind = HomeRowKind(snapshotValue: row.kind) else { return nil }
            let items = row.itemIDs.compactMap { itemsByID[$0] }
            guard !items.isEmpty else { return nil }
            return HomeRow(
                id: row.id,
                kind: kind,
                style: HomeRowStyle(rawValue: row.style) ?? .portrait,
                hub: hub(row.hub, items: items),
            )
        })
    }

    func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        let key = "hub:\(hub.id):\(hub.key)"
        return try await policy.read(
            network: { try await base.items(in: hub, startIndex: startIndex, limit: limit) },
            write: { page in
                guard startIndex == 0 else {
                    policy.store.store(displayItems: page.items, owner: policy.owner)
                    return
                }
                policy.store.store(list: page.items, key: key, owner: policy.owner)
            },
            fallback: {
                let items = policy.store.list(key: key, owner: policy.owner)?.items ?? hub.items
                let start = min(startIndex, items.count)
                let end = min(start + limit, items.count)
                return MediaPage(items: Array(items[start ..< end]), startIndex: start, totalCount: items.count)
            },
        )
    }

    private func save(_ content: HomeContent) {
        let rows = content.rows.map { row in
            HomeRowSnapshot(
                id: row.id,
                kind: row.kind.snapshotValue,
                style: row.style.rawValue,
                hub: hub(row.hub, items: []),
                itemIDs: row.items.map(\.id),
            )
        }
        policy.store.store(
            list: content.rows.flatMap(\.items),
            key: Self.homeKey,
            payload: policy.store.encode(rows),
            owner: policy.owner,
        )
    }

    /// Offline home: downloads first, "Continue watching" rebuilt from local watch state, then the last cached hubs
    /// without the ones that have nothing playable.
    private func offlineHome() -> HomeContent? {
        let store = policy.store
        let owner = policy.owner
        let downloadedIDs = store.downloadedItemIDs(owner: owner)
        var rows: [HomeRow] = []

        let downloads = store.mediaItems(ids: store.downloadedItemIDsByDate(owner: owner), owner: owner)
        if !downloads.isEmpty {
            rows.append(HomeRow(
                id: ["home", owner.server.provider.rawValue, owner.server.id].joined(separator: ":")
                    + Self.offlineDownloadsRowSuffix,
                kind: .hub,
                style: .portrait,
                hub: Hub(
                    id: "offline.downloads",
                    key: "",
                    hubKey: nil,
                    title: String(localized: "offline.home.downloads"),
                    size: downloads.count,
                    more: false,
                    items: downloads.map(MediaDisplayItem.playable),
                ),
            ))
        }

        let inProgress = store.inProgressItems(owner: owner)
            .sorted { lhs, rhs in
                let lhsDownloaded = downloadedIDs.contains(lhs.id)
                let rhsDownloaded = downloadedIDs.contains(rhs.id)
                if lhsDownloaded != rhsDownloaded {
                    return lhsDownloaded
                }
                return (lhs.lastViewedAt ?? .distantPast) > (rhs.lastViewedAt ?? .distantPast)
            }
        if !inProgress.isEmpty {
            rows.append(.continueWatching(server: owner.server, hub: Hub(
                id: "offline.continueWatching",
                key: "",
                hubKey: nil,
                title: String(localized: "offline.home.continueWatching"),
                size: inProgress.count,
                more: false,
                items: inProgress.map(MediaDisplayItem.playable),
            )))
        }

        let cachedRows = cachedHome()?.rows.filter { $0.kind != .continueWatching } ?? []
        for row in cachedRows where row.items.contains(where: { item in
            isAvailableOffline(item, downloadedIDs: downloadedIDs)
        }) {
            rows.append(row)
        }
        return rows.isEmpty ? nil : HomeContent(rows: rows)
    }

    private func isAvailableOffline(_ item: MediaDisplayItem, downloadedIDs: Set<String>) -> Bool {
        guard let media = item.playableItem else { return false }
        switch media.kind {
        case .series:
            return policy.store.episodes(ofSeries: media.id, owner: policy.owner)
                .contains { downloadedIDs.contains($0.id) }
        case .season:
            return policy.store.children(of: media.id, kind: .episode, owner: policy.owner)
                .contains { downloadedIDs.contains($0.id) }
        default:
            return downloadedIDs.contains(media.id)
        }
    }

    private func hub(_ hub: Hub, items: [MediaDisplayItem]) -> Hub {
        Hub(
            id: hub.id,
            key: hub.key,
            hubKey: hub.hubKey,
            title: hub.title,
            size: hub.size,
            more: hub.more,
            items: items,
        )
    }
}

private extension HomeRowKind {
    var snapshotValue: String {
        switch self {
        case .continueWatching:
            "continueWatching"
        case .nextUp:
            "nextUp"
        case .hub:
            "hub"
        }
    }

    init?(snapshotValue: String) {
        switch snapshotValue {
        case "continueWatching":
            self = .continueWatching
        case "nextUp":
            self = .nextUp
        case "hub":
            self = .hub
        default:
            return nil
        }
    }
}
