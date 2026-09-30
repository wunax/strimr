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

    /// Offline home: the downloads row, then the last cached home as it was online. Unplayable items stay visible
    /// and are dimmed by the cards, so the layout does not change when the connection drops.
    private func offlineHome() -> HomeContent? {
        let store = policy.store
        let owner = policy.owner
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

        let locallyInProgress = store.locallyInProgressItems(owner: owner)
        let cachedRows = cachedHome()?.rows ?? []
        if let index = cachedRows.firstIndex(where: { $0.kind == .continueWatching }) {
            rows += cachedRows.enumerated().compactMap { offset, row in
                guard offset == index else { return row }
                let items = continueWatchingItems(row.items, locallyInProgress: locallyInProgress)
                return items.isEmpty ? nil : HomeRow(
                    id: row.id,
                    kind: row.kind,
                    style: row.style,
                    hub: hub(row.hub, items: items),
                )
            }
        } else {
            if !locallyInProgress.isEmpty {
                rows.append(.continueWatching(server: owner.server, hub: Hub(
                    id: "offline.continueWatching",
                    key: "",
                    hubKey: nil,
                    title: String(localized: "offline.home.continueWatching"),
                    size: locallyInProgress.count,
                    more: false,
                    items: locallyInProgress.map(MediaDisplayItem.playable),
                )))
            }
            rows += cachedRows
        }
        return rows.isEmpty ? nil : HomeContent(rows: rows)
    }

    /// The cached server hub, with what was watched offline moved to the front and what was finished offline removed,
    /// mirroring what the server will return once the progress is synchronized.
    private func continueWatchingItems(
        _ snapshot: [MediaDisplayItem],
        locallyInProgress: [MediaItem],
    ) -> [MediaDisplayItem] {
        let snapshotIDs = snapshot.compactMap(\.playableItem?.id)
        let finishedLocally = Set(policy.store.watchStates(itemIDs: snapshotIDs, owner: policy.owner, localOnly: true)
            .filter(\.value.played)
            .keys)
        let movedToFront = Set(locallyInProgress.map(\.id))
        let remaining = snapshot.filter { item in
            guard let id = item.playableItem?.id else { return true }
            return !movedToFront.contains(id) && !finishedLocally.contains(id)
        }
        return locallyInProgress.map(MediaDisplayItem.playable) + remaining
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
