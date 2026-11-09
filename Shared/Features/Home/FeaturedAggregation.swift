import Foundation

/// Picks the titles of the home hero from the candidates of every server.
enum FeaturedAggregation {
    static let defaultCount = 8
    static let minimumCount = 3

    /// Slots of each reason, in the order they are filled.
    static let quotas: [(FeaturedReason, Int)] = [
        (.curated, 2),
        (.recentlyAdded, 3),
        (.newSeason, 1),
        (.trending, 1),
        (.rediscover, 2),
    ]

    /// Reasons that take the slots others could not fill.
    static let fallbackOrder: [FeaturedReason] = [.recentlyAdded, .rediscover, .newSeason, .trending, .curated]

    /// Joins the candidates of a server's libraries. When every library failed, the error is thrown so the server
    /// counts as unanswered and the home keeps its saved selection instead of an empty one.
    static func merge(_ libraries: [Result<[FeaturedCandidate], Error>]) throws -> [FeaturedCandidate] {
        let succeeded = libraries.compactMap { try? $0.get() }
        if succeeded.isEmpty, case let .failure(error)? = libraries.first {
            throw error
        }
        return succeeded.flatMap(\.self)
    }

    /// - Parameters:
    ///   - servers: each server's candidates, in the profile's server order.
    ///   - watching: items of the merged Continue Watching and Next Up rows, which the hero never repeats.
    ///   - previous: today's selection, whose titles keep their place while still eligible.
    static func select(
        _ servers: [ServerFeaturedCandidates],
        excluding watching: [MediaItem],
        previous: [MediaIdentity] = [],
        seed: FeaturedSeed,
        count: Int = defaultCount,
        minimum: Int = minimumCount,
    ) -> [FeaturedCandidate] {
        let serverOrder = servers.map(\.server)
        let pool = deduplicated(
            servers.flatMap(\.candidates).filter(isEligible),
            serverOrder: serverOrder,
            excluding: watching,
        )
        let poolByID = Dictionary(pool.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

        let kept = previous.compactMap { poolByID[$0] }.prefix(count)
        var selected = Array(kept)
        var selectedIDs = Set(selected.map(\.id))
        let queues = queuesByReason(pool, serverOrder: serverOrder, seed: seed)
        let startOffset = serverOrder.isEmpty ? 0 : Int(seed.hash("servers") % UInt64(serverOrder.count))

        func take(_ reason: FeaturedReason, upTo limit: Int) {
            guard limit > 0, var queue = queues[reason] else { return }
            var taken = 0
            var serverIndex = startOffset
            while taken < limit, queue.contains(where: { !$0.isEmpty }) {
                let index = serverIndex % queue.count
                serverIndex += 1
                while let candidate = queue[index].first {
                    queue[index].removeFirst()
                    if selectedIDs.insert(candidate.id).inserted {
                        selected.append(candidate)
                        taken += 1
                        break
                    }
                }
            }
        }

        for (reason, quota) in quotas {
            let alreadyKept = selected.count { $0.reason == reason }
            take(reason, upTo: min(quota - alreadyKept, count - selected.count))
        }
        for reason in fallbackOrder {
            take(reason, upTo: count - selected.count)
        }

        let ordered = placed(ordered(selected, serverOrder: serverOrder, seed: seed), previous: previous)
        return ordered.count >= minimum ? ordered : []
    }

    // MARK: - Filtering

    static func isEligible(_ candidate: FeaturedCandidate) -> Bool {
        let item = candidate.item
        guard item.type == .movie || item.type == .series, item.artPath != nil else { return false }
        let state = item.watchState
        if state.isPlayed || (state.resumePosition ?? 0) > 0 {
            return false
        }
        // A new season is precisely about a series the user started.
        if candidate.reason != .newSeason, let viewed = item.viewedLeafCount, viewed > 0 {
            return false
        }
        return true
    }

    /// One candidate per title: the copy of the first server in the profile's order, on the same server the one with
    /// artwork then the most recent, with the strongest reason of the group. A title the user is watching on any
    /// server is dropped.
    static func deduplicated(
        _ candidates: [FeaturedCandidate],
        serverOrder: [ServerIdentity],
        excluding watching: [MediaItem],
    ) -> [FeaturedCandidate] {
        let rank = Dictionary(serverOrder.enumerated().map { ($1, $0) }, uniquingKeysWith: { first, _ in first })
        let watchingKeys = Set(watching.flatMap(\.matchDescriptor.matchKeys))
        let watchingIdentities = Set(watching.map(\.identity))
        let watchedSeries = Set(watching.compactMap { item in
            item.grandparentRatingKey.map { MediaIdentity(server: item.identity.server, itemID: $0) }
        })

        let sorted = candidates.enumerated().sorted { lhs, rhs in
            let left = rank[lhs.element.server] ?? .max
            let right = rank[rhs.element.server] ?? .max
            return left == right ? lhs.offset < rhs.offset : left < right
        }.map(\.element)

        return MediaMatching.group(sorted) { $0.item.matchDescriptor }.compactMap { group in
            let isWatched = group.contains { candidate in
                watchingIdentities.contains(candidate.id)
                    || watchedSeries.contains(candidate.id)
                    || !candidate.item.matchDescriptor.matchKeys.isDisjoint(with: watchingKeys)
            }
            guard !isWatched, let strongest = group.min(by: { $0.reason < $1.reason }) else { return nil }
            let copy = group.min { lhs, rhs in
                let left = rank[lhs.server] ?? .max
                let right = rank[rhs.server] ?? .max
                if left != right {
                    return left < right
                }
                let leftArt = lhs.item.artPath != nil
                let rightArt = rhs.item.artPath != nil
                if leftArt != rightArt {
                    return leftArt
                }
                return (lhs.addedAt ?? .distantPast) > (rhs.addedAt ?? .distantPast)
            } ?? strongest
            return copy.with(reason: strongest.reason, from: strongest)
        }
    }

    // MARK: - Selection

    /// For each reason, one queue per server in the profile's order. Recent reasons follow the date they were added,
    /// the others the day's draw.
    private static func queuesByReason(
        _ pool: [FeaturedCandidate],
        serverOrder: [ServerIdentity],
        seed: FeaturedSeed,
    ) -> [FeaturedReason: [[FeaturedCandidate]]] {
        var queues: [FeaturedReason: [[FeaturedCandidate]]] = [:]
        for reason in FeaturedReason.allCases {
            let candidates = pool.filter { $0.reason == reason }
            guard !candidates.isEmpty else { continue }
            queues[reason] = serverOrder.map { server in
                let own = candidates.filter { $0.server == server }
                switch reason {
                case .recentlyAdded, .newSeason:
                    return stableSorted(own) { ($0.addedAt ?? .distantPast) > ($1.addedAt ?? .distantPast) }
                case .curated, .trending, .rediscover:
                    return shuffled(own, seed: seed)
                }
            }
        }
        return queues
    }

    static func shuffled(_ candidates: [FeaturedCandidate], seed: FeaturedSeed) -> [FeaturedCandidate] {
        candidates
            .map { (candidate: $0, key: seed.hash("\($0.server.stableKey)|\($0.item.id)")) }
            .sorted { $0.key < $1.key }
            .map(\.candidate)
    }

    // MARK: - Order

    /// Servers take turns, starting with the one holding the strongest title. Within a server, titles go by reason,
    /// alternating movies and series.
    static func ordered(
        _ selected: [FeaturedCandidate],
        serverOrder: [ServerIdentity],
        seed _: FeaturedSeed,
    ) -> [FeaturedCandidate] {
        var lists = serverOrder.map { server in
            alternatingKinds(stableSorted(selected.filter { $0.server == server }) { $0.reason < $1.reason })
        }.filter { !$0.isEmpty }
        guard !lists.isEmpty else { return [] }

        let start = lists.indices.min { lhs, rhs in
            let left = lists[lhs][0].reason
            let right = lists[rhs][0].reason
            return left == right ? lhs < rhs : left < right
        } ?? 0
        var result: [FeaturedCandidate] = []
        var index = start
        while lists.contains(where: { !$0.isEmpty }) {
            let current = index % lists.count
            index += 1
            guard !lists[current].isEmpty else { continue }
            result.append(lists[current].removeFirst())
        }
        return result
    }

    private static func alternatingKinds(_ candidates: [FeaturedCandidate]) -> [FeaturedCandidate] {
        var result: [FeaturedCandidate] = []
        var remaining = candidates
        while let first = remaining.first {
            let group = remaining.prefix { $0.reason == first.reason }
            remaining.removeFirst(group.count)
            var movies = group.filter { $0.item.type == .movie }
            var series = group.filter { $0.item.type != .movie }
            var takesMovie = first.item.type == .movie
            while !movies.isEmpty || !series.isEmpty {
                if takesMovie, !movies.isEmpty {
                    result.append(movies.removeFirst())
                } else if !series.isEmpty {
                    result.append(series.removeFirst())
                } else {
                    result.append(movies.removeFirst())
                }
                takesMovie.toggle()
            }
        }
        return result
    }

    /// Titles of today's previous selection keep their slot; new titles fill the free ones in order.
    static func placed(_ ordered: [FeaturedCandidate], previous: [MediaIdentity]) -> [FeaturedCandidate] {
        guard !previous.isEmpty else { return ordered }
        let selectedIDs = Set(ordered.map(\.id))
        var slots: [FeaturedCandidate?] = Array(repeating: nil, count: max(ordered.count, previous.count))
        let byID = Dictionary(ordered.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        for (index, id) in previous.enumerated() where selectedIDs.contains(id) {
            slots[index] = byID[id]
        }
        let placedIDs = Set(slots.compactMap { $0?.id })
        var newcomers = ordered.filter { !placedIDs.contains($0.id) }.makeIterator()
        for index in slots.indices where slots[index] == nil {
            slots[index] = newcomers.next()
        }
        return slots.compactMap(\.self)
    }

    private static func stableSorted(
        _ items: [FeaturedCandidate],
        by areInIncreasingOrder: (FeaturedCandidate, FeaturedCandidate) -> Bool,
    ) -> [FeaturedCandidate] {
        items.enumerated().sorted { lhs, rhs in
            if areInIncreasingOrder(lhs.element, rhs.element) {
                return true
            }
            if areInIncreasingOrder(rhs.element, lhs.element) {
                return false
            }
            return lhs.offset < rhs.offset
        }.map(\.element)
    }
}
