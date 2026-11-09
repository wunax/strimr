import Foundation
@testable import Strimr
import Testing

struct MediaItemMappingTests {
    private let server = ServerIdentity(provider: .plex, id: "server-a")

    @Test func `plex release date maps to utc midnight`() throws {
        let hub = try #require(
            Fixtures.decode(PlexHubMediaContainer.self, from: "plex-continue-watching").mediaContainer.hub?.first,
        )
        let items = (hub.metadata ?? []).map { MediaItem(plexItem: $0, server: server) }

        #expect(items[0].releaseDate == ISO8601DateFormatter().date(from: "2021-06-18T00:00:00Z"))
        #expect(items[1].releaseDate == nil)
    }

    @Test func `plex theme falls back to the series theme`() throws {
        let hub = try #require(
            Fixtures.decode(PlexHubMediaContainer.self, from: "plex-continue-watching").mediaContainer.hub?.first,
        )
        let items = (hub.metadata ?? []).map { MediaItem(plexItem: $0, server: server) }

        #expect(items[0].themePath == nil)
        #expect(items[1].themePath == "/library/metadata/100/theme/1700000000")
    }

    @Test func `plex edition title maps to the item`() throws {
        let items = try (Fixtures.decode(PlexItemMediaContainer.self, from: "plex-section-editions")
            .mediaContainer.metadata ?? []).map { MediaItem(plexItem: $0, server: server) }

        #expect(items[0].editionTitle == nil)
        #expect(items[1].editionTitle == "Black and White")
    }

    @Test func `plex date parser rejects malformed values`() {
        #expect(PlexDate.date(from: "not-a-date") == nil)
        #expect(PlexDate.date(from: "2021-06-18 00:00:00") == ISO8601DateFormatter().date(from: "2021-06-18T00:00:00Z"))
    }

    @Test func `plex logo comes from the clear logo image`() throws {
        let items = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-metadata-logo")
            .mediaContainer.metadata ?? []
        let movie = MediaItem(plexItem: items[0], server: server)
        let show = MediaItem(plexItem: items[1], server: server)

        #expect(movie.logoPath == "/library/metadata/201/clearLogo/1700000000")
        #expect(movie.preferredLogoPath == movie.logoPath)
        #expect(show.logoPath == nil)
    }

    @Test func `plex episodes in hubs carry no series logo`() throws {
        let hub = try #require(
            Fixtures.decode(PlexHubMediaContainer.self, from: "plex-continue-watching").mediaContainer.hub?.first,
        )
        let episode = try MediaItem(plexItem: #require(hub.metadata?.last), server: server)

        #expect(episode.logoPath == nil)
        #expect(episode.preferredLogoPath == nil)
    }

    @Test func `jellyfin logo comes from the item image tags`() throws {
        let jellyfinServer = ServerIdentity(provider: .jellyfin, id: "server-1")
        let movie = try MediaItem(
            jellyfinItem: Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie"),
            server: jellyfinServer,
        )

        #expect(movie.logoPath == "jellyfin-artwork://movie-1/Logo?tag=logo-tag")
        #expect(movie.grandparentLogoPath == nil)
        #expect(movie.preferredLogoPath == movie.logoPath)
    }

    @Test func `jellyfin episode uses the parent logo`() throws {
        let jellyfinServer = ServerIdentity(provider: .jellyfin, id: "server-1")
        let episode = try MediaItem(
            jellyfinItem: Fixtures.decode(JellyfinItem.self, from: "jellyfin-episode"),
            server: jellyfinServer,
        )

        #expect(episode.logoPath == nil)
        #expect(episode.grandparentLogoPath == "jellyfin-artwork://series-1/Logo?tag=series-logo-tag")
        #expect(episode.preferredLogoPath == episode.grandparentLogoPath)
    }
}
