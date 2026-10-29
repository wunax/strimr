@testable import Strimr
import Testing

@MainActor
struct MediaDetailPlaybackEpisodeTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `offers the episode the series was opened from`() {
        let requested = MediaItem.make(id: "s3e3", server: server, type: .episode)
        let onDeck = MediaItem.make(id: "s2e3", server: server, type: .episode)

        #expect(MediaDetailViewModel.playbackEpisode(requested: requested, onDeck: onDeck)?.id == "s3e3")
    }

    @Test func `moves on to next up once the requested episode is watched`() {
        let requested = MediaItem.make(id: "s3e3", server: server, type: .episode, viewCount: 1)
        let onDeck = MediaItem.make(id: "s3e4", server: server, type: .episode)

        #expect(MediaDetailViewModel.playbackEpisode(requested: requested, onDeck: onDeck)?.id == "s3e4")
    }

    @Test func `offers a rewatched episode while it is in progress`() {
        let requested = MediaItem.make(id: "s1e2", server: server, type: .episode, viewOffset: 600, viewCount: 1)
        let onDeck = MediaItem.make(id: "s3e4", server: server, type: .episode)

        #expect(MediaDetailViewModel.playbackEpisode(requested: requested, onDeck: onDeck)?.id == "s1e2")
    }

    @Test func `keeps next up without a requested episode`() {
        let onDeck = MediaItem.make(id: "s1e1", server: server, type: .episode)

        #expect(MediaDetailViewModel.playbackEpisode(requested: nil, onDeck: onDeck)?.id == "s1e1")
    }
}
