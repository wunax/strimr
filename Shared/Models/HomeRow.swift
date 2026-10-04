import Foundation

enum HomeRowKind: Hashable {
    case continueWatching
    case nextUp
    case hub
}

enum HomeRowStyle: String, Hashable {
    case landscape
    case portrait
}

struct HomeRow: Identifiable, Hashable {
    let id: String
    let kind: HomeRowKind
    let style: HomeRowStyle
    let hub: Hub
    /// Name of the row's server, shown when the profile has several servers.
    var serverName: String?

    var title: String {
        hub.title
    }

    var items: [MediaDisplayItem] {
        hub.items
    }

    var canOpenDetail: Bool {
        hub.canOpenDetail
    }

    /// Reprendre and Next Up are merged across servers, so their ids carry no server.
    static let continueWatchingID = "home:continueWatching"
    static let nextUpID = "home:nextUp"

    /// Server of a per-server row id (`home:<provider>:<serverID>:…`); `nil` for merged rows.
    static func server(fromRowID rowID: String) -> ServerIdentity? {
        let parts = rowID.split(separator: ":", maxSplits: 3, omittingEmptySubsequences: false)
        guard parts.count >= 3, parts[0] == "home", let provider = MediaProvider(rawValue: String(parts[1])),
              !parts[2].isEmpty
        else { return nil }
        return ServerIdentity(provider: provider, id: String(parts[2]))
    }

    /// Maps the pre-multi-server ids of Reprendre and Next Up to their merged ids; other ids are unchanged.
    static func migratedRowID(_ rowID: String) -> String {
        let parts = rowID.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 4, parts[0] == "home", MediaProvider(rawValue: String(parts[1])) != nil else {
            return rowID
        }
        switch parts[3] {
        case "continueWatching":
            return continueWatchingID
        case "nextUp":
            return nextUpID
        default:
            return rowID
        }
    }

    static func continueWatching(server: ServerIdentity, hub: Hub) -> HomeRow {
        HomeRow(
            id: ["home", server.provider.rawValue, server.id, "continueWatching"].joined(separator: ":"),
            kind: .continueWatching,
            style: .landscape,
            hub: hub,
        )
    }

    static func nextUp(server: ServerIdentity, hub: Hub) -> HomeRow {
        HomeRow(
            id: ["home", server.provider.rawValue, server.id, "nextUp"].joined(separator: ":"),
            kind: .nextUp,
            style: .portrait,
            hub: hub,
        )
    }

    static func providerHub(server: ServerIdentity, hub: Hub) -> HomeRow {
        let route = routePath(hub.key)
        let hubRoute = hub.hubKey.map(routePath) ?? ""
        let sourceID = [hub.id, hubRoute, route].joined(separator: ":")
        return HomeRow(
            id: ["home", server.provider.rawValue, server.id, "hub", sourceID].joined(separator: ":"),
            kind: .hub,
            style: .portrait,
            hub: hub,
        )
    }

    private nonisolated static func routePath(_ value: String) -> String {
        URLComponents(string: value)?.path
            ?? value.split(separator: "?", maxSplits: 1).first.map(String.init)
            ?? value
    }
}

struct HomeRowPreferences: Codable, Equatable {
    var orderedRowIDs: [String] = []
    var hiddenRowIDs: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderedRowIDs = try container.decodeIfPresent([String].self, forKey: .orderedRowIDs) ?? []
        hiddenRowIDs = try container.decodeIfPresent([String].self, forKey: .hiddenRowIDs) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case orderedRowIDs
        case hiddenRowIDs
    }

    func orderedRows(from rows: [HomeRow]) -> [HomeRow] {
        PreferenceOrder.sorted(rows.filter(\.hub.hasItems), id: \.id, order: orderedRowIDs)
    }

    func visibleRows(from rows: [HomeRow]) -> [HomeRow] {
        let hiddenIDs = Set(hiddenRowIDs)
        return orderedRows(from: rows).filter { !hiddenIDs.contains($0.id) }
    }

    mutating func setRow(_ id: String, visible: Bool) {
        var hiddenIDs = Set(hiddenRowIDs)
        if visible {
            hiddenIDs.remove(id)
        } else {
            hiddenIDs.insert(id)
        }
        hiddenRowIDs = hiddenIDs.sorted()
    }

    mutating func setOrder(_ availableRowIDs: [String]) {
        orderedRowIDs = PreferenceOrder.merged(stored: orderedRowIDs, available: availableRowIDs)
    }

    /// Drops the ids of rows that belong to `servers`, e.g. after their account was removed.
    mutating func removeRows(of servers: Set<ServerIdentity>) {
        let belongs: (String) -> Bool = { HomeRow.server(fromRowID: $0).map(servers.contains) ?? false }
        orderedRowIDs.removeAll(where: belongs)
        hiddenRowIDs.removeAll(where: belongs)
    }

    var isEmpty: Bool {
        orderedRowIDs.isEmpty && hiddenRowIDs.isEmpty
    }
}
