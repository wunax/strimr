@testable import Strimr
import Testing

@MainActor
struct JellyfinContinueEpisodeTests {
    private let episodes: [String: JellyfinItem]

    init() throws {
        let items = try Fixtures.decode([JellyfinItem].self, from: "jellyfin-series-progress")
        episodes = Dictionary(uniqueKeysWithValues: items.map { ($0.id, $0) })
    }

    @Test func `resumes a show started mid-way`() {
        let episode = JellyfinCatalogService.continueEpisode(
            nextUp: episodes["episode-s1e1"],
            resumable: episodes["episode-s3e3"],
        )

        #expect(episode?.id == "episode-s3e3")
    }

    @Test func `keeps next up over an in-progress episode earlier in the show`() {
        let episode = JellyfinCatalogService.continueEpisode(
            nextUp: episodes["episode-s3e4"],
            resumable: episodes["episode-s1e2"],
        )

        #expect(episode?.id == "episode-s3e4")
    }

    @Test func `uses whichever episode is available`() {
        #expect(JellyfinCatalogService.continueEpisode(nextUp: episodes["episode-s1e1"], resumable: nil)?
            .id == "episode-s1e1")
        #expect(JellyfinCatalogService.continueEpisode(nextUp: nil, resumable: episodes["episode-s3e3"])?
            .id == "episode-s3e3")
        #expect(JellyfinCatalogService.continueEpisode(nextUp: nil, resumable: nil) == nil)
    }
}
