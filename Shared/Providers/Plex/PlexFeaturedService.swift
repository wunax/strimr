import Foundation

/// Candidates of a Plex server for the home hero.
@MainActor
struct PlexFeaturedService {
    let context: PlexAPIContext
    let server: ServerIdentity

    func candidates(hiddenLibraryIDs: Set<String>, now: Date = Date()) async throws -> [FeaturedCandidate] {
        let sections = try await SectionRepository(context: context).getSections().mediaContainer.directory ?? []
        let visible = sections.filter {
            !hiddenLibraryIDs.contains($0.key) && ($0.type == .movie || $0.type == .show) && Int($0.key) != nil
        }
        guard !visible.isEmpty else { return [] }

        async let curated = curatedCandidates(sections: visible, hidesSome: !hiddenLibraryIDs.isEmpty)
        let bySection = await withTaskGroup(of: (Int, [FeaturedCandidate]).self) { group in
            for (index, section) in visible.enumerated() {
                group.addTask { @MainActor in
                    do {
                        return try await (index, sectionCandidates(section, now: now))
                    } catch {
                        // A library that fails is left out so it does not take the hero down.
                        if !Task.isCancelled, !error.isCancellation {
                            ErrorReporter.capture(error)
                        }
                        return (index, [])
                    }
                }
            }
            var values: [(Int, [FeaturedCandidate])] = []
            for await value in group {
                values.append(value)
            }
            return values.sorted { $0.0 < $1.0 }.flatMap(\.1)
        }
        try Task.checkCancellation()
        return await curated + bySection
    }

    private func sectionCandidates(_ section: PlexSection, now: Date) async throws -> [FeaturedCandidate] {
        guard let sectionID = Int(section.key) else { return [] }
        let type = section.type == .movie ? 1 : 2
        async let recent = unwatched(sectionID: sectionID, type: type, sort: "addedAt:desc", size: Self.poolSize)
        async let rated = unwatched(sectionID: sectionID, type: type, sort: "audienceRating:desc", size: 60)
        var candidates = try await PlexFeaturedMapping.recentlyAdded(recent, server: server, now: now)
        candidates += try await PlexFeaturedMapping.rediscover(rated, server: server, now: now)
        if section.type == .show {
            candidates += try await newSeasons(sectionID: sectionID, now: now)
        }
        return candidates
    }

    private func newSeasons(sectionID: Int, now: Date) async throws -> [FeaturedCandidate] {
        let episodes = try await unwatched(sectionID: sectionID, type: 4, sort: "addedAt:desc", size: 100)
        let additions = PlexFeaturedMapping.recentAdditions(episodes: episodes, now: now)
        guard !additions.isEmpty else { return [] }
        let keys = Array(additions.keys.prefix(Self.poolSize))
        let shows = try await MetadataRepository(context: context).getGuids(ratingKeys: keys)
            .mediaContainer.metadata ?? []
        return PlexFeaturedMapping.newSeasons(shows: shows, additions: additions, server: server)
    }

    private func curatedCandidates(sections: [PlexSection], hidesSome: Bool) async -> [FeaturedCandidate] {
        let params = hidesSome ? HubRepository.HubParams(sectionIds: sections.compactMap { Int($0.key) }) : nil
        do {
            let hubs = try await HubRepository(context: context).getPromotedHub(params: params).mediaContainer.hub
            return PlexFeaturedMapping.curated(hubs: hubs ?? [], server: server)
        } catch {
            if !Task.isCancelled, !error.isCancellation {
                ErrorReporter.capture(error)
            }
            return []
        }
    }

    /// `unwatched=1` still lists started series, which the mapping filters out.
    private func unwatched(sectionID: Int, type: Int, sort: String, size: Int) async throws -> [PlexItem] {
        let response = try await SectionRepository(context: context).getSectionItems(
            path: "/library/sections/\(sectionID)/all",
            queryItems: [
                URLQueryItem(name: "type", value: String(type)),
                URLQueryItem(name: "unwatched", value: "1"),
                URLQueryItem(name: "sort", value: sort),
                HubRepository.includeGuids,
            ],
            // Plex ignores the size without a start, and would list the whole library.
            pagination: PlexPagination(start: 0, size: size),
        )
        return response.mediaContainer.metadata ?? []
    }

    static let poolSize = 30
}

/// The pure part of the Plex candidates, kept apart to be tested on server responses.
enum PlexFeaturedMapping {
    static let recentWindow: TimeInterval = 30 * 86400
    static let rediscoverMinimumAge: TimeInterval = 182 * 86400
    static let rediscoverMinimumRating = 7.0

    /// Plex reports started and even fully watched series as unwatched: only the episode counts tell.
    static func isUnwatched(_ item: PlexItem) -> Bool {
        switch item.type {
        case .movie:
            (item.viewCount ?? 0) == 0 && (item.viewOffset ?? 0) == 0
        case .show:
            (item.viewedLeafCount ?? 0) == 0 && (item.leafCount ?? 1) > 0
        default:
            false
        }
    }

    static func addedDate(_ item: PlexItem) -> Date? {
        item.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    static func recentlyAdded(_ items: [PlexItem], server: ServerIdentity, now _: Date) -> [FeaturedCandidate] {
        items.filter { isUnwatched($0) && $0.art != nil }.map {
            FeaturedCandidate(
                item: MediaItem(plexItem: $0, server: server),
                reason: .recentlyAdded,
                addedAt: addedDate($0),
            )
        }
    }

    /// Well rated titles added a while ago. A server without ratings falls back to its older unwatched titles.
    static func rediscover(_ items: [PlexItem], server: ServerIdentity, now: Date) -> [FeaturedCandidate] {
        let old = items.filter { item in
            guard isUnwatched(item), item.art != nil, let added = addedDate(item) else { return false }
            return now.timeIntervalSince(added) >= rediscoverMinimumAge
        }
        let hasRatings = items.contains { $0.audienceRating != nil }
        let kept = hasRatings ? old.filter { ($0.audienceRating ?? 0) >= rediscoverMinimumRating } : old
        return kept.prefix(PlexFeaturedService.poolSize).map {
            FeaturedCandidate(
                item: MediaItem(plexItem: $0, server: server),
                reason: .rediscover,
                addedAt: addedDate($0),
            )
        }
    }

    struct Addition: Equatable {
        let addedAt: Date
        /// The season whose first episode was added, when there is one.
        let seasonNumber: Int?
    }

    /// Series with unwatched episodes added lately, by series key, newest first in insertion order.
    static func recentAdditions(episodes: [PlexItem], now: Date) -> [String: Addition] {
        var additions: [String: Addition] = [:]
        for episode in episodes where episode.type == .episode {
            guard let key = episode.grandparentRatingKey, let added = addedDate(episode),
                  now.timeIntervalSince(added) <= recentWindow
            else { continue }
            let premiere = episode.index == 1 ? episode.parentIndex : nil
            let current = additions[key]
            additions[key] = Addition(
                addedAt: max(current?.addedAt ?? added, added),
                seasonNumber: [current?.seasonNumber, premiere].compactMap(\.self).max(),
            )
        }
        return additions
    }

    /// Series the user started and has not finished, which got new episodes.
    static func newSeasons(
        shows: [PlexItem],
        additions: [String: Addition],
        server: ServerIdentity,
    ) -> [FeaturedCandidate] {
        shows.compactMap { show in
            guard show.type == .show, show.art != nil, let addition = additions[show.ratingKey],
                  let viewed = show.viewedLeafCount, let total = show.leafCount, viewed > 0, total > viewed
            else { return nil }
            return FeaturedCandidate(
                item: MediaItem(plexItem: show, server: server),
                reason: .newSeason,
                addedAt: addition.addedAt,
                newSeasonNumber: addition.seasonNumber,
            )
        }
    }

    /// Only the hubs of collections the owner promoted: Plex also promotes themed hubs of its own (`movie.curated.*`),
    /// recently added and on deck hubs, which are not a curation.
    static func curated(hubs: [PlexHub], server: ServerIdentity) -> [FeaturedCandidate] {
        hubs.filter(isCollectionHub).flatMap { hub in
            (hub.metadata ?? []).filter { ($0.type == .movie || $0.type == .show) && isUnwatched($0) && $0.art != nil }
                .map {
                    FeaturedCandidate(
                        item: MediaItem(plexItem: $0, server: server),
                        reason: .curated,
                        addedAt: addedDate($0),
                        collectionTitle: hub.title,
                    )
                }
        }
    }

    static func isCollectionHub(_ hub: PlexHub) -> Bool {
        let identifier = hub.hubIdentifier.lowercased()
        return identifier.contains("collection") && !identifier.contains(".curated.")
    }
}
