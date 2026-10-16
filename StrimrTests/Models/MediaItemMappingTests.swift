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

    @Test func `plex date parser rejects malformed values`() {
        #expect(PlexDate.date(from: "not-a-date") == nil)
        #expect(PlexDate.date(from: "2021-06-18 00:00:00") == ISO8601DateFormatter().date(from: "2021-06-18T00:00:00Z"))
    }
}
