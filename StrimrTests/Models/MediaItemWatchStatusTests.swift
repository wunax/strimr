import Foundation
@testable import Strimr
import Testing

struct MediaItemWatchStatusTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `full protection swaps an unwatched episode title for its number`() {
        let episode = MediaItem.make(id: "1", server: server, title: "Pilot", type: .episode, episodeNumber: 3)

        #expect(episode.spoilerSafeTitle(at: .full) == String(localized: "media.labels.episodeNumber \(3)"))
        #expect(episode.spoilerSafeTitle(at: .thumbnails) == "Pilot")
        #expect(episode.spoilerSafeTitle(at: .off) == "Pilot")
    }

    @Test func `watched episodes and movies keep their title`() {
        let watched = MediaItem.make(id: "1", server: server, title: "Pilot", type: .episode, viewCount: 1)
        let movie = MediaItem.make(id: "2", server: server, title: "Movie")

        #expect(watched.spoilerSafeTitle(at: .full) == "Pilot")
        #expect(movie.spoilerSafeTitle(at: .full) == "Movie")
    }

    @Test func `an unnumbered episode says its title is hidden`() {
        let special = MediaItem.make(id: "1", server: server, title: "Special", type: .episode)

        #expect(special.spoilerSafeTitle(at: .full) == String(localized: "media.spoilerProtection.titleHidden"))
    }
}
