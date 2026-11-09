import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexFeaturedMappingTests {
    private let server = ServerIdentity(provider: .plex, id: "plex-a")
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func `started and finished series reported as unwatched are dropped`() throws {
        let shows = try items("plex-featured-shows")

        let recent = PlexFeaturedMapping.recentlyAdded(shows, server: server, now: now)

        #expect(recent.map(\.item.id) == ["101", "104", "105"])
        #expect(recent.first?.reason == .recentlyAdded)
        #expect(recent.first?.addedAt == Date(timeIntervalSince1970: 1_799_500_000))
        #expect(recent.first?.item.externalIDs.tmdb == "9001")
    }

    @Test func `rediscover keeps well rated titles added a while ago`() throws {
        let rediscover = try PlexFeaturedMapping.rediscover(items("plex-featured-shows"), server: server, now: now)

        #expect(rediscover.map(\.item.id) == ["104"])
    }

    @Test func `new episodes of a started series make a new season candidate`() throws {
        let additions = try PlexFeaturedMapping.recentAdditions(episodes: items("plex-featured-episodes"), now: now)

        #expect(additions["201"]?.seasonNumber == 4)
        #expect(additions["202"] == PlexFeaturedMapping.Addition(
            addedAt: Date(timeIntervalSince1970: 1_799_700_000),
            seasonNumber: nil,
        ))
        #expect(additions["203"] == nil)

        let candidates = try PlexFeaturedMapping.newSeasons(
            shows: items("plex-featured-returning-shows"),
            additions: additions,
            server: server,
        )

        #expect(candidates.map(\.item.id) == ["201", "202"])
        #expect(candidates.map(\.newSeasonNumber) == [4, nil])
        #expect(candidates.allSatisfy { $0.reason == .newSeason })
    }

    @Test func `new season lookups keep the series with the newest additions`() {
        let additions = (0 ..< 40).reduce(into: [String: PlexFeaturedMapping.Addition]()) { additions, index in
            additions["\(index)"] = PlexFeaturedMapping.Addition(
                addedAt: Date(timeIntervalSince1970: TimeInterval(index)),
                seasonNumber: nil,
            )
        }

        let keys = PlexFeaturedMapping.newestSeriesKeys(additions, limit: 3)

        #expect(keys == ["39", "38", "37"])
    }

    @Test func `only promoted collections are curated`() throws {
        let hubs = try Fixtures.decode(PlexHubMediaContainer.self, from: "plex-featured-promoted").mediaContainer.hub

        let curated = PlexFeaturedMapping.curated(hubs: hubs ?? [], server: server)

        #expect(curated.map(\.item.id) == ["403"])
        #expect(curated.first?.collectionTitle == "Staff Picks")
    }

    private func items(_ fixture: String) throws -> [PlexItem] {
        try Fixtures.decode(PlexItemMediaContainer.self, from: fixture).mediaContainer.metadata ?? []
    }
}
