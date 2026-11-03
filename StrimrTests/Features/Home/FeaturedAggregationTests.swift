import Foundation
@testable import Strimr
import Testing

@MainActor
struct FeaturedAggregationTests {
    private let plex = ServerIdentity(provider: .plex, id: "plex-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "jf-b")
    private let seed = FeaturedSeed(profileID: "profile", day: 100)

    @Test func `a single server fills the quotas by reason`() {
        let candidates = (1 ... 5).map { candidate("r\($0)", .recentlyAdded, addedAt: Double(10 - $0)) }
            + (1 ... 4).map { candidate("d\($0)", .rediscover) }
            + [candidate("s1", .newSeason, type: .series)]

        let selection = FeaturedAggregation.select([servers(plex, candidates)], excluding: [], seed: seed)

        #expect(selection.count == 8)
        #expect(selection.count { $0.reason == .recentlyAdded } == 5)
        #expect(selection.count { $0.reason == .rediscover } == 2)
        #expect(selection.count { $0.reason == .newSeason } == 1)
        #expect(selection.first?.reason == .recentlyAdded)
        #expect(selection.filter { $0.reason == .recentlyAdded }.map(\.item.id).prefix(3) == ["r1", "r2", "r3"])
    }

    @Test func `a single Jellyfin server works the same way`() {
        let candidates = (1 ... 3).map { candidate("j\($0)", .recentlyAdded, on: jellyfin, addedAt: Double($0)) }

        let selection = FeaturedAggregation.select([servers(jellyfin, candidates)], excluding: [], seed: seed)

        #expect(selection.map(\.item.id) == ["j3", "j2", "j1"])
    }

    @Test func `servers strictly take turns and the others go on once one runs out`() {
        let plexCandidates = (1 ... 6).map { candidate("p\($0)", .recentlyAdded, addedAt: Double(10 - $0)) }
        let jellyfinCandidates = (1 ... 2).map {
            candidate("j\($0)", .recentlyAdded, on: jellyfin, addedAt: Double(10 - $0))
        }

        let selection = FeaturedAggregation.select(
            [servers(plex, plexCandidates), servers(jellyfin, jellyfinCandidates)],
            excluding: [],
            seed: seed,
        )

        let order = selection.map(\.server)
        #expect(Array(order.prefix(4)) == [plex, jellyfin, plex, jellyfin] || Array(order.prefix(4)) == [
            jellyfin,
            plex,
            jellyfin,
            plex,
        ])
        #expect(order.count { $0 == jellyfin } == 2)
        #expect(order.suffix(4).allSatisfy { $0 == plex })
    }

    @Test func `a title on two servers keeps the copy of the first server`() {
        let ids = ExternalIDs(tmdb: "42")
        let selection = FeaturedAggregation.select(
            [
                servers(plex, [
                    candidate("p1", .recentlyAdded, ids: ids),
                    candidate("p2", .rediscover),
                    candidate("p3", .rediscover),
                ]),
                servers(jellyfin, [candidate("j1", .rediscover, on: jellyfin, ids: ids)]),
            ],
            excluding: [],
            seed: seed,
        )

        #expect(selection.map(\.item.id).sorted() == ["p1", "p2", "p3"])
        #expect(selection.first { $0.item.id == "p1" }?.reason == .recentlyAdded)
    }

    @Test func `a title twice on one server keeps a single copy, the one with artwork`() {
        let ids = ExternalIDs(tmdb: "7")
        let selection = FeaturedAggregation.deduplicated(
            [
                candidate("edition", .recentlyAdded, type: .series, ids: ids, hasArt: false),
                candidate("main", .recentlyAdded, type: .series, ids: ids),
            ],
            serverOrder: [plex],
            excluding: [],
        )

        #expect(selection.map(\.item.id) == ["main"])
    }

    @Test func `the strongest reason of a group wins`() {
        let ids = ExternalIDs(tmdb: "9")
        let selection = FeaturedAggregation.deduplicated(
            [candidate("a", .rediscover, ids: ids), candidate("b", .trending, on: jellyfin, ids: ids)],
            serverOrder: [plex, jellyfin],
            excluding: [],
        )

        #expect(selection.map(\.item.id) == ["a"])
        #expect(selection.first?.reason == .trending)
    }

    @Test func `a started series reported as unwatched is dropped`() {
        let started = candidate("started", .recentlyAdded, type: .series, viewedLeafCount: 2)
        let fresh = candidate("fresh", .recentlyAdded, type: .series, viewedLeafCount: 0)
        let newSeason = candidate("back", .newSeason, type: .series, viewedLeafCount: 5)

        #expect(!FeaturedAggregation.isEligible(started))
        #expect(FeaturedAggregation.isEligible(fresh))
        #expect(FeaturedAggregation.isEligible(newSeason))
    }

    @Test func `watched, in progress or artless titles are not eligible`() {
        #expect(!FeaturedAggregation.isEligible(candidate("w", .rediscover, viewCount: 1)))
        #expect(!FeaturedAggregation.isEligible(candidate("p", .rediscover, viewOffset: 120)))
        #expect(!FeaturedAggregation.isEligible(candidate("a", .rediscover, hasArt: false)))
        #expect(!FeaturedAggregation.isEligible(candidate("e", .rediscover, type: .episode)))
    }

    @Test func `a title in continue watching on another server is excluded`() {
        let ids = ExternalIDs(imdb: "tt1")
        let watching = MediaItem.make(id: "cw", server: jellyfin, externalIDs: ids)

        let selection = FeaturedAggregation.deduplicated(
            [candidate("p1", .recentlyAdded, ids: ids), candidate("p2", .recentlyAdded)],
            serverOrder: [plex, jellyfin],
            excluding: [watching],
        )

        #expect(selection.map(\.item.id) == ["p2"])
    }

    @Test func `a series with an episode in next up is excluded`() {
        let nextEpisode = MediaItem.make(id: "ep", server: plex, type: .episode, seriesID: "show")

        let selection = FeaturedAggregation.deduplicated(
            [candidate("show", .newSeason, type: .series, viewedLeafCount: 3), candidate(
                "other",
                .newSeason,
                type: .series,
            )],
            serverOrder: [plex],
            excluding: [nextEpisode],
        )

        #expect(selection.map(\.item.id) == ["other"])
    }

    @Test func `a started series with a new season absent from next up stays`() {
        let selection = FeaturedAggregation.deduplicated(
            [candidate("show", .newSeason, type: .series, viewedLeafCount: 3)],
            serverOrder: [plex],
            excluding: [MediaItem.make(id: "ep", server: plex, type: .episode, seriesID: "elsewhere")],
        )

        #expect(selection.map(\.item.id) == ["show"])
    }

    @Test func `a series excluded through its copy on another server`() {
        let ids = ExternalIDs(tmdb: "55")
        let nextEpisode = MediaItem.make(id: "ep", server: jellyfin, type: .episode, seriesID: "j-show")

        let selection = FeaturedAggregation.deduplicated(
            [
                candidate("p-show", .newSeason, type: .series, ids: ids, viewedLeafCount: 1),
                candidate("j-show", .newSeason, on: jellyfin, type: .series, ids: ids, viewedLeafCount: 1),
            ],
            serverOrder: [plex, jellyfin],
            excluding: [nextEpisode],
        )

        #expect(selection.isEmpty)
    }

    @Test func `a failing server is simply absent`() {
        let selection = FeaturedAggregation.select(
            [servers(plex, (1 ... 4).map { candidate("p\($0)", .rediscover) })],
            excluding: [],
            seed: seed,
        )

        #expect(selection.count == 4)
        #expect(selection.allSatisfy { $0.server == plex })
    }

    @Test func `fewer than three titles show no hero`() {
        let selection = FeaturedAggregation.select(
            [servers(plex, [candidate("a", .recentlyAdded), candidate("b", .rediscover)])],
            excluding: [],
            seed: seed,
        )

        #expect(selection.isEmpty)
    }

    @Test func `the same seed gives the same draw and the next day another`() {
        let candidates = (1 ... 30).map { candidate("d\($0)", .rediscover) }
        let input = [servers(plex, candidates)]

        let first = FeaturedAggregation.select(input, excluding: [], seed: seed).map(\.item.id)
        let again = FeaturedAggregation.select(input, excluding: [], seed: seed).map(\.item.id)
        let tomorrow = FeaturedAggregation.select(
            input,
            excluding: [],
            seed: FeaturedSeed(profileID: "profile", day: 101),
        ).map(\.item.id)

        #expect(first == again)
        #expect(first != tomorrow)
    }

    @Test func `titles of the day keep their place and a watched one is replaced`() {
        let candidates = (1 ... 12).map { candidate("d\($0)", .rediscover) }
        let first = FeaturedAggregation.select([servers(plex, candidates)], excluding: [], seed: seed)
        let watchedID = first[2].id
        let remaining = candidates.filter { $0.id != watchedID }

        let second = FeaturedAggregation.select(
            [servers(plex, remaining)],
            excluding: [],
            previous: first.map(\.id),
            seed: FeaturedSeed(profileID: "profile", day: 100),
        )

        #expect(second.count == first.count)
        for index in first.indices where index != 2 {
            #expect(second[index].id == first[index].id)
        }
        #expect(second[2].id != watchedID)
    }

    @Test func `slots of an empty reason go to the others`() {
        let candidates = (1 ... 10).map { candidate("r\($0)", .recentlyAdded, addedAt: Double(20 - $0)) }

        let selection = FeaturedAggregation.select([servers(plex, candidates)], excluding: [], seed: seed)

        #expect(selection.count == 8)
        #expect(selection.allSatisfy { $0.reason == .recentlyAdded })
    }

    @Test func `the daily seed is the same all day long`() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/Paris"))
        let morning = Date(timeIntervalSince1970: 1_800_000_000)
        let evening = morning.addingTimeInterval(6 * 3600)

        #expect(FeaturedSeed.make(profileID: "p", date: morning, calendar: calendar)
            == FeaturedSeed.make(profileID: "p", date: evening, calendar: calendar))
        #expect(FeaturedSeed.make(profileID: "p", date: morning, calendar: calendar)
            != FeaturedSeed.make(profileID: "p", date: morning.addingTimeInterval(86400), calendar: calendar))
    }

    // MARK: - Helpers

    private func servers(_ server: ServerIdentity, _ candidates: [FeaturedCandidate]) -> ServerFeaturedCandidates {
        ServerFeaturedCandidates(server: server, candidates: candidates)
    }

    private func candidate(
        _ id: String,
        _ reason: FeaturedReason,
        on server: ServerIdentity? = nil,
        type: MediaKind = .movie,
        ids: ExternalIDs = ExternalIDs(),
        addedAt: TimeInterval? = nil,
        hasArt: Bool = true,
        viewCount: Int? = nil,
        viewOffset: TimeInterval? = nil,
        viewedLeafCount: Int? = nil,
    ) -> FeaturedCandidate {
        let server = server ?? plex
        let base = MediaItem.make(
            id: id,
            server: server,
            type: type,
            externalIDs: ids,
            viewOffset: viewOffset,
            viewCount: viewCount,
            artPath: hasArt ? "/art/\(id)" : nil,
        )
        let item = viewedLeafCount.map { viewed in
            MediaItem(
                id: base.id, identity: base.identity, guid: base.guid, summary: nil, title: base.title,
                type: base.type, parentRatingKey: nil, grandparentRatingKey: nil, genres: [], year: nil,
                duration: nil, videoResolution: nil, rating: nil, ratings: [], contentRating: nil, studio: nil,
                tagline: nil, thumbPath: nil, artPath: base.artPath, artworkCornerColors: nil, viewOffset: nil,
                viewCount: nil, childCount: nil, leafCount: 10, viewedLeafCount: viewed, grandparentTitle: nil,
                parentTitle: nil, parentIndex: nil, index: nil, grandparentThumbPath: nil, grandparentArtPath: nil,
                parentThumbPath: nil, externalIDs: ids,
            )
        } ?? base
        return FeaturedCandidate(
            item: item,
            reason: reason,
            addedAt: addedAt.map { Date(timeIntervalSince1970: $0) },
        )
    }
}
