import Foundation
@testable import Strimr
import Testing

struct MediaItemLabelsTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `episode label joins season, episode and title`() {
        let episode = MediaItem.make(
            id: "1",
            server: server,
            title: "Pilot",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: 2,
        )

        #expect(episode.episodeTitleLabel == "S1 · E2 · Pilot")
    }

    @Test func `episode label without a title keeps season and episode`() {
        let episode = MediaItem.make(
            id: "1",
            server: server,
            title: " ",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: 2,
        )

        #expect(episode.episodeTitleLabel == "S1 · E2")
    }

    @Test func `episode label without numbering falls back to the title`() {
        let episode = MediaItem.make(id: "1", server: server, title: "Special", type: .episode)

        #expect(episode.episodeTitleLabel == "Special")
    }

    @Test func `movies have no episode label`() {
        let movie = MediaItem.make(id: "1", server: server, title: "Movie")

        #expect(movie.episodeTitleLabel == nil)
    }
}
