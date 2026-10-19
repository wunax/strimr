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
    /// Library of the row, shown in the settings where rows of several libraries share a title.
    var libraryName: String?
    /// The server's owner excluded the row's library from the home screen.
    var isExcludedFromServerHome = false

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

    /// Plex hub ids read `<context>.<sectionID>[.<variant>]`, e.g. `movie.genre.1.7`: the variant (a genre, an actor)
    /// is picked by the server and changes over time, so it is dropped.
    static func stablePlexHubID(_ hubID: String) -> String {
        let components = hubID.split(separator: ".", omittingEmptySubsequences: false)
        guard let sectionIndex = components.firstIndex(where: { Int($0) != nil }) else { return hubID }
        return components[...sectionIndex].joined(separator: ".")
    }

    /// Library section of a Plex hub id, `nil` for hubs that span libraries.
    static func plexSectionID(fromHubID hubID: String) -> String? {
        hubID.split(separator: ".").first { Int($0) != nil }.map(String.init)
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

    static func hubRowIDPrefix(server: ServerIdentity) -> String {
        ["home", server.provider.rawValue, server.id, "hub", ""].joined(separator: ":")
    }

    static func providerHub(server: ServerIdentity, hub: Hub) -> HomeRow {
        let sourceID: String = if server.provider == .plex {
            // A Plex hubKey lists the hub's items, so it changes whenever media is added.
            stablePlexHubID(hub.id)
        } else {
            [hub.id, hub.hubKey.map(routePath) ?? "", routePath(hub.key)].joined(separator: ":")
        }
        return HomeRow(
            id: hubRowIDPrefix(server: server) + sourceID,
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
    /// Rows turned on although the server does not put them on its home.
    var shownRowIDs: [String] = []

    init() {}

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        orderedRowIDs = try container.decodeIfPresent([String].self, forKey: .orderedRowIDs) ?? []
        hiddenRowIDs = try container.decodeIfPresent([String].self, forKey: .hiddenRowIDs) ?? []
        shownRowIDs = try container.decodeIfPresent([String].self, forKey: .shownRowIDs) ?? []
    }

    private enum CodingKeys: String, CodingKey {
        case orderedRowIDs
        case hiddenRowIDs
        case shownRowIDs
    }

    func orderedRows(from rows: [HomeRow]) -> [HomeRow] {
        PreferenceOrder.sorted(rows.filter(\.hub.hasItems), id: \.id, order: orderedRowIDs)
    }

    func visibleRows(from rows: [HomeRow]) -> [HomeRow] {
        let hiddenIDs = Set(hiddenRowIDs)
        return orderedRows(from: rows).filter { !hiddenIDs.contains($0.id) }
    }

    /// A row is shown when the user turned it on, or when the server puts it on its home and the user did not hide it.
    func isVisible(_ id: String, onServerHome: Bool) -> Bool {
        !hiddenRowIDs.contains(id) && (onServerHome || shownRowIDs.contains(id))
    }

    mutating func setRow(_ id: String, visible: Bool) {
        var hiddenIDs = Set(hiddenRowIDs)
        var shownIDs = Set(shownRowIDs)
        if visible {
            hiddenIDs.remove(id)
            shownIDs.insert(id)
        } else {
            hiddenIDs.insert(id)
            shownIDs.remove(id)
        }
        hiddenRowIDs = hiddenIDs.sorted()
        shownRowIDs = shownIDs.sorted()
    }

    mutating func setOrder(_ availableRowIDs: [String]) {
        orderedRowIDs = PreferenceOrder.merged(stored: orderedRowIDs, available: availableRowIDs)
    }

    /// Drops the ids of rows that belong to `servers`, e.g. after their account was removed.
    mutating func removeRows(of servers: Set<ServerIdentity>) {
        let belongs: (String) -> Bool = { HomeRow.server(fromRowID: $0).map(servers.contains) ?? false }
        orderedRowIDs.removeAll(where: belongs)
        hiddenRowIDs.removeAll(where: belongs)
        shownRowIDs.removeAll(where: belongs)
    }

    var isEmpty: Bool {
        orderedRowIDs.isEmpty && hiddenRowIDs.isEmpty && shownRowIDs.isEmpty
    }
}
