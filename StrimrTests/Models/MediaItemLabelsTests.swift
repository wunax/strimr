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

    @Test func `cards show the edition after the year`() {
        let movie = MediaItem.make(id: "1", server: server, editionTitle: "Director's Cut", year: 1982)
        let undated = MediaItem.make(id: "2", server: server, editionTitle: "Director's Cut")

        #expect(movie.secondaryLabel == "1982 · Director's Cut")
        #expect(undated.secondaryLabel == "Director's Cut")
        #expect(MediaItem.make(id: "3", server: server, editionTitle: "  ", year: 1982).secondaryLabel == "1982")
    }

    @Test func `the regular cut sorts before named editions`() {
        let editions = [
            MediaItem.make(id: "1", server: server, editionTitle: "Final Cut"),
            MediaItem.make(id: "2", server: server, editionTitle: "Director's Cut"),
            MediaItem.make(id: "3", server: server),
        ].sorted(by: MediaItem.editionOrder)

        #expect(editions.map(\.id) == ["3", "2", "1"])
        #expect(editions[0].editionLabel == String(localized: "media.editions.standard"))
        #expect(editions[1].editionLabel == "Director's Cut")
    }

    @Test func `movies have no episode label`() {
        let movie = MediaItem.make(id: "1", server: server, title: "Movie")

        #expect(movie.episodeTitleLabel == nil)
    }
}
