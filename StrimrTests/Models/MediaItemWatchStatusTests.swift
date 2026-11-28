import Foundation
@testable import Strimr
import Testing

struct MediaItemWatchStatusTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `full protection swaps an unwatched episode title for its number`() {
        let episode = MediaItem.make(id: "1", server: server, title: "Pilot", type: .episode, episodeNumber: 3)

        #expect(episode.spoilerSafeTitle(at: .full) == String(localized: "media.labels.episodeNumber \("3")"))
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

    @Test func `plex seasons count their viewed leaves`() throws {
        let seasons = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-seasons").mediaContainer
            .metadata ?? []
        let progress = seasons.map { MediaItem(plexItem: $0).seasonProgress }

        #expect(progress == [
            EpisodeProgress(watched: 25, total: 25),
            EpisodeProgress(watched: 5, total: 25),
            EpisodeProgress(watched: 0, total: 10),
        ])
    }

    @Test func `jellyfin seasons count episodes from the child count`() throws {
        let server = ServerIdentity(provider: .jellyfin, id: "server-1")
        let seasons = try Fixtures.decode([JellyfinItem].self, from: "jellyfin-seasons")
        let progress = seasons.map { MediaItem(jellyfinItem: $0, server: server).seasonProgress }

        #expect(progress == [
            EpisodeProgress(watched: 8, total: 8),
            EpisodeProgress(watched: 3, total: 12),
            EpisodeProgress(watched: 0, total: 6),
        ])
    }

    @Test func `chips skip seasons not started yet`() throws {
        let seasons = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-seasons").mediaContainer
            .metadata ?? []
        let progress = seasons.map { MediaItem(plexItem: $0).startedSeasonProgress }

        #expect(progress.map { $0?.isComplete } == [true, false, nil])
    }

    @Test func `only seasons have a season progress`() {
        let episode = MediaItem.make(id: "1", server: ServerIdentity(provider: .plex, id: "plex"), type: .episode)

        #expect(episode.seasonProgress == nil)
    }
}
