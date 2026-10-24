import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinPlaylistMappingTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `maps playlist items to entries keyed by playlist item ID`() throws {
        let result = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-playlist-items")
        let entries = JellyfinPlaylistService.entries(from: result.items, server: server)

        #expect(entries.map(\.entryID) == ["entry-1", "entry-2", "movie-2", "movie-2", "movie-3"])
        #expect(entries.map(\.media.id) == ["movie-1", "episode-1", "movie-2", "movie-2", "movie-3"])
    }

    @Test func `keeps repeated entries apart`() throws {
        let result = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-playlist-items")
        let entries = JellyfinPlaylistService.entries(from: result.items, server: server)

        #expect(entries.map(\.id) == ["entry-1", "entry-2", "movie-2", "movie-2#1", "movie-3"])
    }

    @Test func `reads ownership and media type of a playlist`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-playlist")

        #expect(item.canDelete == false)
        #expect(item.mediaType == "Video")
        #expect(item.kind == .playlist)
    }
}
