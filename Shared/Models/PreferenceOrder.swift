import Foundation

/// Ordering shared by home rows and libraries: stored ids keep their place even while their server is unreachable or
/// disabled, and unknown items follow the known ones in their natural order.
enum PreferenceOrder {
    static func sorted<Item, ID: Hashable>(_ items: [Item], id: (Item) -> ID, order storedOrder: [ID]) -> [Item] {
        var order: [ID: Int] = [:]
        for (index, itemID) in storedOrder.enumerated() where order[itemID] == nil {
            order[itemID] = index
        }
        return items.enumerated()
            .sorted { lhs, rhs in
                switch (order[id(lhs.element)], order[id(rhs.element)]) {
                case let (left?, right?):
                    left == right ? lhs.offset < rhs.offset : left < right
                case (_?, nil):
                    true
                case (nil, _?):
                    false
                case (nil, nil):
                    lhs.offset < rhs.offset
                }
            }
            .map(\.element)
    }

    /// Writes the new order of the available ids into the slots they occupied in the stored order, leaving the slots of
    /// absent ids untouched, then appends the ids that were not stored yet.
    static func merged<ID: Hashable>(stored: [ID], available: [ID]) -> [ID] {
        var uniqueAvailable: [ID] = []
        var availableSet = Set<ID>()
        for itemID in available where availableSet.insert(itemID).inserted {
            uniqueAvailable.append(itemID)
        }

        var merged: [ID] = []
        var storedSet = Set<ID>()
        for itemID in stored where storedSet.insert(itemID).inserted {
            merged.append(itemID)
        }
        let availableSlots = merged.indices.filter { availableSet.contains(merged[$0]) }
        for (slot, itemID) in zip(availableSlots, uniqueAvailable) {
            merged[slot] = itemID
        }
        storedSet = Set(merged)
        merged.append(contentsOf: uniqueAvailable.filter { !storedSet.contains($0) })
        return merged
    }
}
