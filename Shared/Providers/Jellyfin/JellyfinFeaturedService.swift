import Foundation

/// Candidates of a Jellyfin server for the home hero.
@MainActor
struct JellyfinFeaturedService {
    let catalog: JellyfinCatalogService
    let server: ServerIdentity

    static let poolSize = 30

    func candidates(hiddenLibraryIDs: Set<String>, now: Date = Date()) async throws -> [FeaturedCandidate] {
        let libraries = try await catalog.libraries().filter {
            let type = $0.collectionType?.lowercased()
            return !hiddenLibraryIDs.contains($0.id) && (type == "movies" || type == "tvshows")
        }
        let byLibrary = await withTaskGroup(of: (Int, [FeaturedCandidate]).self) { group in
            for (index, library) in libraries.enumerated() {
                group.addTask { @MainActor in
                    do {
                        let isSeries = library.collectionType?.lowercased() == "tvshows"
                        return try await (index, libraryCandidates(library.id, isSeries: isSeries, now: now))
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
        return byLibrary
    }

    private func libraryCandidates(_ libraryID: String, isSeries: Bool, now: Date) async throws -> [FeaturedCandidate] {
        let type = isSeries ? "Series" : "Movie"
        // A series' `DateCreated` is often unset, so series go by their newest episode.
        let recentSort = isSeries ? "DateLastContentAdded" : "DateCreated"
        let unplayedWithBackdrop = [
            URLQueryItem(name: "IsPlayed", value: "false"),
            URLQueryItem(name: "ImageTypes", value: "Backdrop"),
        ]
        async let recent = catalog.featuredItems(
            parentID: libraryID,
            includeTypes: type,
            sortBy: recentSort,
            limit: Self.poolSize,
            extraQuery: unplayedWithBackdrop,
        )
        async let rated = catalog.featuredItems(
            parentID: libraryID,
            includeTypes: type,
            sortBy: "CommunityRating",
            limit: 60,
            extraQuery: unplayedWithBackdrop,
        )
        var candidates = try await JellyfinFeaturedMapping.recentlyAdded(recent, server: server)
        candidates += try await JellyfinFeaturedMapping.rediscover(rated, server: server, now: now)
        if isSeries {
            candidates += try await newSeasons(libraryID: libraryID, now: now)
        }
        return candidates
    }

    private func newSeasons(libraryID: String, now: Date) async throws -> [FeaturedCandidate] {
        let latest = try await catalog.latest(parentID: libraryID, limit: Self.poolSize)
        let additions = JellyfinFeaturedMapping.additions(latest: latest)
        guard !additions.isEmpty else { return [] }
        let series = try await catalog.featuredItems(
            includeTypes: "Series",
            limit: additions.count,
            extraQuery: [URLQueryItem(name: "Ids", value: additions.keys.sorted().joined(separator: ","))],
        )
        return JellyfinFeaturedMapping.newSeasons(series: series, additions: additions, server: server, now: now)
    }
}

/// The pure part of the Jellyfin candidates, kept apart to be tested on server responses.
enum JellyfinFeaturedMapping {
    static let recentWindow: TimeInterval = 30 * 86400
    static let rediscoverMinimumAge: TimeInterval = 182 * 86400
    static let rediscoverMinimumRating = 7.0

    /// `IsPlayed=false` keeps started series: only the played percentage tells them apart.
    static func isUnstarted(_ item: JellyfinItem) -> Bool {
        let userData = item.userData
        guard userData?.played != true, (userData?.playbackPositionTicks ?? 0) == 0 else { return false }
        return (userData?.playedPercentage ?? 0) == 0
    }

    static func hasBackdrop(_ item: JellyfinItem) -> Bool {
        !(item.backdropImageTags ?? []).isEmpty
    }

    /// `DateCreated` of a series is often `0001-01-01`; its newest episode date stands in.
    static func addedDate(_ item: JellyfinItem) -> Date? {
        let created = item.dateCreated.flatMap(JellyfinDate.date(from:)).flatMap { $0 > minimumValidDate ? $0 : nil }
        if item.kind == .series {
            return item.dateLastMediaAdded.flatMap(JellyfinDate.date(from:)) ?? created
        }
        return created
    }

    private static let minimumValidDate = Date(timeIntervalSince1970: 0)

    static func recentlyAdded(_ items: [JellyfinItem], server: ServerIdentity) -> [FeaturedCandidate] {
        items.filter { isUnstarted($0) && hasBackdrop($0) }.map {
            FeaturedCandidate(
                item: MediaItem(jellyfinItem: $0, server: server),
                reason: .recentlyAdded,
                addedAt: addedDate($0),
            )
        }
    }

    /// Well rated titles added a while ago. A server without ratings falls back to its older unwatched titles.
    static func rediscover(_ items: [JellyfinItem], server: ServerIdentity, now: Date) -> [FeaturedCandidate] {
        let old = items.filter { item in
            guard isUnstarted(item), hasBackdrop(item), let added = addedDate(item) else { return false }
            return now.timeIntervalSince(added) >= rediscoverMinimumAge
        }
        let hasRatings = items.contains { $0.communityRating != nil }
        let kept = hasRatings ? old.filter { ($0.communityRating ?? 0) >= rediscoverMinimumRating } : old
        return kept.prefix(JellyfinFeaturedService.poolSize).map {
            FeaturedCandidate(
                item: MediaItem(jellyfinItem: $0, server: server),
                reason: .rediscover,
                addedAt: addedDate($0),
            )
        }
    }

    /// Series that got new content, by series id, with the new season when a whole one or its first episode came.
    /// `Items/Latest` groups a season added at once into a `Season`, and a few episodes into `Episode`s.
    static func additions(latest: [JellyfinItem]) -> [String: Int?] {
        var additions: [String: Int?] = [:]
        for item in latest {
            guard let seriesID = item.seriesID else { continue }
            let season: Int? = switch item.kind {
            case .season: item.indexNumber
            case .episode where item.indexNumber == 1: item.parentIndexNumber
            default: nil
            }
            let current = additions[seriesID] ?? nil
            additions[seriesID] = [current, season].compactMap(\.self).max()
        }
        return additions
    }

    /// Series the user started and has not finished, whose newest episode came lately.
    static func newSeasons(
        series: [JellyfinItem],
        additions: [String: Int?],
        server: ServerIdentity,
        now: Date,
    ) -> [FeaturedCandidate] {
        series.compactMap { item in
            guard item.kind == .series, hasBackdrop(item), let addition = additions[item.id],
                  item.userData?.played != true, (item.userData?.playedPercentage ?? 0) > 0,
                  let added = addedDate(item), now.timeIntervalSince(added) <= recentWindow
            else { return nil }
            return FeaturedCandidate(
                item: MediaItem(jellyfinItem: item, server: server),
                reason: .newSeason,
                addedAt: added,
                newSeasonNumber: addition,
            )
        }
    }
}
