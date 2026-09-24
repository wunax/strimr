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

    var title: String {
        hub.title
    }

    var items: [MediaDisplayItem] {
        hub.items
    }

    var canOpenDetail: Bool {
        hub.canOpenDetail
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

    nonisolated private static func routePath(_ value: String) -> String {
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
        let availableRows = rows.filter(\.hub.hasItems)
        var order: [String: Int] = [:]
        for (index, rowID) in orderedRowIDs.enumerated() where order[rowID] == nil {
            order[rowID] = index
        }
        return availableRows.enumerated()
            .sorted { lhs, rhs in
                let lhsOrder = order[lhs.element.id]
                let rhsOrder = order[rhs.element.id]
                switch (lhsOrder, rhsOrder) {
                case let (left?, right?):
                    return left == right ? lhs.offset < rhs.offset : left < right
                case (_?, nil):
                    return true
                case (nil, _?):
                    return false
                case (nil, nil):
                    return lhs.offset < rhs.offset
                }
            }
            .map(\.element)
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
        var uniqueAvailableIDs: [String] = []
        var availableIDs = Set<String>()
        for rowID in availableRowIDs where availableIDs.insert(rowID).inserted {
            uniqueAvailableIDs.append(rowID)
        }

        var mergedOrder: [String] = []
        var storedIDs = Set<String>()
        for rowID in orderedRowIDs where storedIDs.insert(rowID).inserted {
            mergedOrder.append(rowID)
        }
        let availableSlots = mergedOrder.indices.filter { availableIDs.contains(mergedOrder[$0]) }

        for (slot, rowID) in zip(availableSlots, uniqueAvailableIDs) {
            mergedOrder[slot] = rowID
        }

        storedIDs = Set(mergedOrder)
        mergedOrder.append(contentsOf: uniqueAvailableIDs.filter { !storedIDs.contains($0) })
        orderedRowIDs = mergedOrder
    }
}
