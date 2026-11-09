import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinFeaturedMappingTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "jf-b")
    private let now = JellyfinDate.date(from: "2027-01-15T10:00:00Z")!

    @Test func `started series and series without a backdrop are dropped`() throws {
        let recent = try JellyfinFeaturedMapping.recentlyAdded(series("jellyfin-featured-series"), server: server)

        #expect(recent.map(\.item.id) == ["s1", "s3"])
        #expect(recent.first?.item.externalIDs.tmdb == "7001")
    }

    @Test func `an unset series creation date falls back to its newest episode`() throws {
        let items = try series("jellyfin-featured-series")

        #expect(JellyfinFeaturedMapping.addedDate(items[0]) == JellyfinDate.date(from: "2027-01-10T10:00:00Z"))
    }

    @Test func `rediscover keeps well rated titles added a while ago`() throws {
        let rediscover = try JellyfinFeaturedMapping.rediscover(
            series("jellyfin-featured-series"),
            server: server,
            now: now,
        )

        #expect(rediscover.map(\.item.id) == ["s3"])
    }

    @Test func `latest additions tell a new season from a few episodes`() throws {
        let latest = try Fixtures.decode([JellyfinItem].self, from: "jellyfin-featured-latest")

        let additions = JellyfinFeaturedMapping.additions(latest: latest)

        #expect(additions["r1"] == .some(4))
        #expect(additions["r2"] == .some(nil))
        #expect(additions["r3"] == .some(3))
        #expect(additions["new-series"] == nil)
    }

    @Test func `only started series with recent content are new season candidates`() throws {
        let latest = try Fixtures.decode([JellyfinItem].self, from: "jellyfin-featured-latest")

        let candidates = try JellyfinFeaturedMapping.newSeasons(
            series: series("jellyfin-featured-returning-series"),
            additions: JellyfinFeaturedMapping.additions(latest: latest),
            server: server,
            now: now,
        )

        #expect(candidates.map(\.item.id) == ["r1"])
        #expect(candidates.first?.newSeasonNumber == 4)
    }

    private func series(_ fixture: String) throws -> [JellyfinItem] {
        try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: fixture).items
    }
}
