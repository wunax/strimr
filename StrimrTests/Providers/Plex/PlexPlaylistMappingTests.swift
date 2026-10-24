import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexPlaylistMappingTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `maps playlist items to entries keyed by playlist item ID`() throws {
        let response = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-playlist-items")
        let entries = PlexPlaylistService.entries(from: response.mediaContainer.metadata ?? [], server: server)

        #expect(entries.map(\.entryID) == ["11", "12"])
        #expect(entries.map(\.media.id) == ["101", "102"])
        #expect(entries.map(\.media.type) == [.movie, .episode])
    }

    @Test func `reads smart playlists as such`() throws {
        let response = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-playlists")
        let playlists = (response.mediaContainer.metadata ?? []).map { PlaylistMediaItem(plexItem: $0, server: server) }

        #expect(playlists.map(\.isSmart) == [false, true])
        #expect(playlists.map(\.leafCount) == [2, 5])
    }

    @Test func `cached playlists without the smart flag read as regular ones`() throws {
        let playlist = PlaylistMediaItem(
            id: "500",
            key: "/playlists/500/items",
            guid: "guid",
            type: .playlist,
            title: "Example Playlist",
            summary: nil,
            compositePath: nil,
            duration: nil,
            leafCount: nil,
            playlistType: "video",
            server: server,
        )
        var json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(playlist)) as? [String: Any])
        json.removeValue(forKey: "isSmart")

        let decoded = try JSONDecoder().decode(
            PlaylistMediaItem.self,
            from: JSONSerialization.data(withJSONObject: json),
        )

        #expect(decoded.isSmart == false)
    }

    @Test func `renaming keeps everything but the title`() {
        let playlist = PlaylistMediaItem(
            id: "500",
            key: "/playlists/500/items",
            guid: "guid",
            type: .playlist,
            title: "Old",
            summary: "Summary",
            compositePath: "/composite",
            duration: 1000,
            leafCount: 3,
            playlistType: "video",
            isSmart: false,
            server: server,
        )

        let renamed = playlist.renamed("New")

        #expect(renamed.title == "New")
        #expect(renamed.id == playlist.id)
        #expect(renamed.leafCount == 3)
        #expect(renamed.server == server)
    }
}
