@testable import Strimr
import Testing

@MainActor
struct MediaDetailMediaChangeTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `series page watches the episode it offers from another season`() throws {
        let series = try #require(PlayableMediaItem(mediaItem: MediaItem.make(
            id: "series",
            server: server,
            type: .series,
        )))
        let viewModel = MediaDetailViewModel(media: series, services: .fake(server: server))
        viewModel.episodes = [MediaItem.make(id: "s1e1", server: server, type: .episode)]
        viewModel.onDeckItem = MediaItem.make(id: "s3e4", server: server, type: .episode)

        #expect(viewModel.shownMediaIDs.isSuperset(of: ["series", "s1e1", "s3e4"]))
        #expect(!viewModel.shownMediaIDs.contains("s2e1"))
    }
}
