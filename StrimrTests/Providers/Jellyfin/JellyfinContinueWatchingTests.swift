@testable import Strimr
import Testing

@MainActor
struct JellyfinContinueWatchingTests {
    private struct Lists: Decodable {
        let resume: [JellyfinItem]
        let nextUp: [JellyfinItem]
        let played: [JellyfinItem]
    }

    private let lists: Lists

    init() throws {
        lists = try Fixtures.decode(Lists.self, from: "jellyfin-continue-watching")
    }

    @Test func `next up episodes are ordered by when their series was last watched`() {
        let items = JellyfinCatalogService.continueWatching(
            resume: lists.resume,
            nextUp: lists.nextUp,
            playedEpisodes: lists.played,
        )

        #expect(items.map(\.id) == ["movie-1", "series-b-s2e1", "series-a-s1e3", "series-c-s1e5"])
    }

    @Test func `a series appears once, at its in-progress episode when it is further along`() {
        let items = JellyfinCatalogService.continueWatching(
            resume: lists.resume,
            nextUp: lists.nextUp,
            playedEpisodes: lists.played,
        )

        #expect(items.count(where: { $0.seriesID == "series-a" }) == 1)
        #expect(items.contains { $0.id == "series-a-s1e3" })
    }

    @Test func `without played history, the first next up series does not fall to the end`() {
        let items = JellyfinCatalogService.continueWatching(
            resume: lists.resume,
            nextUp: lists.nextUp,
            playedEpisodes: [],
        )

        #expect(items.map(\.id) == ["movie-1", "series-a-s1e3", "series-b-s2e1", "series-c-s1e5"])
    }

    @Test func `a series missing from the played episodes keeps next up's order`() {
        let items = JellyfinCatalogService.continueWatching(
            resume: [],
            nextUp: lists.nextUp,
            playedEpisodes: [],
        )

        #expect(items.map(\.id) == ["series-b-s2e1", "series-a-s1e2", "series-c-s1e5"])
    }
}
