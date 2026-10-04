import Foundation

/// Builds the home of a profile from the rows of each server: Reprendre and Next Up are merged across servers and
/// deduplicated, library rows stay one per library.
enum HomeAggregation {
    struct ServerHome {
        let server: ServerIdentity
        let serverName: String
        let rows: [HomeRow]
    }

    /// - Parameters:
    ///   - homes: rows of each server, in the order of the profile's servers.
    ///   - libraryOrder: the profile's library order. Without one, library rows keep their server's order.
    ///   - localPlaybackDate: when an item was last played on this device, which decides between copies.
    static func merge(
        _ homes: [ServerHome],
        libraryOrder: [LibraryIdentity] = [],
        showsServerNames: Bool,
        localPlaybackDate: (MediaIdentity) -> Date? = { _ in nil },
    ) -> [HomeRow] {
        var rows: [HomeRow] = []
        if let continueWatching = mergedRow(
            homes,
            kind: .continueWatching,
            sortsByLastViewed: true,
            localPlaybackDate: localPlaybackDate,
        ) {
            rows.append(continueWatching)
        }
        if let nextUp = mergedRow(
            homes,
            kind: .nextUp,
            sortsByLastViewed: false,
            localPlaybackDate: localPlaybackDate,
        ) {
            rows.append(nextUp)
        }
        let libraryRows = homes.flatMap { home in
            home.rows.filter { $0.kind == .hub }.map { row in
                var row = row
                row.serverName = showsServerNames ? home.serverName : nil
                return row
            }
        }
        rows += PreferenceOrder.sorted(
            libraryRows,
            id: { libraryIdentity(of: $0) },
            order: libraryOrder.map(Optional.some),
        )
        return rows
    }

    /// Library of a "recently added" row: Jellyfin names its hubs after the library, Plex hubs point to their section.
    static func libraryIdentity(of row: HomeRow) -> LibraryIdentity? {
        guard let server = row.hub.server ?? HomeRow.server(fromRowID: row.id) else { return nil }
        let jellyfinPrefix = "jellyfin.latest."
        if row.hub.id.hasPrefix(jellyfinPrefix) {
            return LibraryIdentity(server: server, libraryID: String(row.hub.id.dropFirst(jellyfinPrefix.count)))
        }
        if let sectionID = URLComponents(string: row.hub.key)?.queryItems?
            .first(where: { $0.name == "sectionID" || $0.name == "contentDirectoryID" })?.value
        {
            return LibraryIdentity(server: server, libraryID: sectionID)
        }
        if let sectionID = row.items.lazy.compactMap({ $0.playableItem?.librarySectionID }).first {
            return LibraryIdentity(server: server, libraryID: sectionID)
        }
        return nil
    }

    private static func mergedRow(
        _ homes: [ServerHome],
        kind: HomeRowKind,
        sortsByLastViewed: Bool,
        localPlaybackDate: (MediaIdentity) -> Date?,
    ) -> HomeRow? {
        let sources = homes.compactMap { home in home.rows.first { $0.kind == kind } }
        guard let first = sources.first else { return nil }
        let candidates = sources.flatMap(\.items)
        let ordered = sortsByLastViewed ? sortedByLastViewed(candidates) : candidates
        let items = MediaMatching.group(ordered) { matchDescriptor(of: $0) }.compactMap { group in
            preferredCopy(in: group, localPlaybackDate: localPlaybackDate)
        }
        guard !items.isEmpty else { return nil }
        let id = kind == .continueWatching ? HomeRow.continueWatchingID : HomeRow.nextUpID
        return HomeRow(
            id: id,
            kind: kind,
            style: first.style,
            hub: Hub(
                id: id,
                key: "",
                hubKey: nil,
                title: first.title,
                size: items.count,
                more: false,
                items: items,
            ),
        )
    }

    /// The copy played most recently on this device wins, otherwise the most recent on its server (the group is
    /// already sorted that way).
    private static func preferredCopy(
        in group: [MediaDisplayItem],
        localPlaybackDate: (MediaIdentity) -> Date?,
    ) -> MediaDisplayItem? {
        let local = group.compactMap { item -> (MediaDisplayItem, Date)? in
            guard let identity = item.playableItem?.identity, let date = localPlaybackDate(identity) else { return nil }
            return (item, date)
        }
        return local.max { $0.1 < $1.1 }?.0 ?? group.first
    }

    private static func sortedByLastViewed(_ items: [MediaDisplayItem]) -> [MediaDisplayItem] {
        items.enumerated().sorted { lhs, rhs in
            switch (lhs.element.playableItem?.lastViewedAt, rhs.element.playableItem?.lastViewedAt) {
            case let (left?, right?) where left != right:
                left > right
            case (_?, nil):
                true
            case (nil, _?):
                false
            default:
                lhs.offset < rhs.offset
            }
        }.map(\.element)
    }

    private static func matchDescriptor(of item: MediaDisplayItem) -> MediaMatchDescriptor {
        item.playableItem?.matchDescriptor
            ?? MediaMatchDescriptor(kind: .other, guid: nil, externalIDs: ExternalIDs())
    }
}
