@testable import Strimr
import Testing

@MainActor
struct MediaDetailEpisodesRefreshTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    private var current: [MediaItem] {
        [
            MediaItem.make(id: "s1e1", server: server, type: .episode),
            MediaItem.make(id: "s1e2", server: server, type: .episode),
        ]
    }

    @Test func `refreshing a series keeps its episodes until the season is fetched again`() {
        let episodes = MediaDetailViewModel.episodesAfterLoading(
            [],
            current: current,
            mediaType: .show,
            preservingExistingContent: true,
        )

        #expect(episodes.map(\.id) == ["s1e1", "s1e2"])
    }

    @Test func `loading a series from scratch takes the loaded episodes`() {
        let episodes = MediaDetailViewModel.episodesAfterLoading(
            [],
            current: current,
            mediaType: .show,
            preservingExistingContent: false,
        )

        #expect(episodes.isEmpty)
    }

    @Test func `refreshing a season takes the episodes it loaded`() {
        let loaded = [MediaItem.make(id: "s1e1", server: server, type: .episode, viewCount: 1)]

        let episodes = MediaDetailViewModel.episodesAfterLoading(
            loaded,
            current: current,
            mediaType: .season,
            preservingExistingContent: true,
        )

        #expect(episodes.map(\.id) == ["s1e1"])
    }
}
