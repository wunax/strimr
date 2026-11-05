import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackerItemResolverTests {
    private let detail = FakeTrackerDetailService()
    private let resolver = TrackerItemResolver()

    @Test func `a movie uses its own ids without asking the server`() async throws {
        let item = try await resolver.resolve(TrackerFixtures.movieItem(), detail: detail)

        #expect(item == TrackerItem(kind: .movie, ids: TrackerFixtures.movieIDs, title: "Movie", year: 2020))
        #expect(detail.itemRequests.isEmpty)
    }

    @Test func `a movie without ids is fetched again, as not every plex call asks for them`() async throws {
        detail.items["movie"] = TrackerFixtures.movieItem()

        let item = try await resolver.resolve(
            TrackerFixtures.movieItem(ids: ExternalIDs()),
            detail: detail,
        )

        #expect(item?.ids == TrackerFixtures.movieIDs)
    }

    @Test func `a movie with no id anywhere is not sent`() async throws {
        let empty = TrackerFixtures.movieItem(ids: ExternalIDs())
        detail.items["movie"] = empty

        #expect(try await resolver.resolve(empty, detail: detail) == nil)
    }

    @Test func `an episode uses the ids of its series`() async throws {
        detail.items["series"] = TrackerFixtures.seriesItem()

        let item = try await resolver.resolve(TrackerFixtures.episodeItem(number: 3), detail: detail)

        #expect(item == TrackerFixtures.episode(3))
    }

    @Test func `the series is fetched once for its episodes`() async throws {
        detail.items["series"] = TrackerFixtures.seriesItem()

        _ = try await resolver.resolve(TrackerFixtures.episodeItem(id: "e1", number: 1), detail: detail)
        _ = try await resolver.resolve(TrackerFixtures.episodeItem(id: "e2", number: 2), detail: detail)

        #expect(detail.itemRequests == ["series"])
    }

    @Test func `an episode without a series or a number is not sent`() async throws {
        #expect(try await resolver.resolve(TrackerFixtures.episodeItem(seriesID: nil), detail: detail) == nil)

        let unnumbered = MediaItem.make(
            id: "e",
            server: TrackerFixtures.server,
            type: .episode,
            seasonNumber: 1,
            seriesID: "series",
        )
        #expect(try await resolver.resolve(unnumbered, detail: detail) == nil)
    }

    @Test func `other kinds are not sent`() async throws {
        let clip = MediaItem.make(id: "clip", server: TrackerFixtures.server, type: .clip)

        #expect(try await resolver.resolve(clip, detail: detail) == nil)
    }

    @Test func `a series expands into the episodes of its seasons`() async throws {
        let season = MediaItem.make(id: "s1", server: TrackerFixtures.server, type: .season)
        detail.seasonsByID["series"] = [season]
        detail.episodesByID["s1"] = [TrackerFixtures.episodeItem(id: "e1"), TrackerFixtures.episodeItem(id: "e2")]

        let episodes = try await resolver.expand(TrackerFixtures.seriesItem(), detail: detail)

        #expect(episodes.map(\.id) == ["e1", "e2"])
    }
}
