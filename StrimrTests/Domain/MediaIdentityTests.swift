import Foundation
@testable import Strimr
import Testing

struct MediaIdentityTests {
    @Test func `library identity has a stable text form`() throws {
        let identity = LibraryIdentity(server: ServerIdentity(provider: .plex, id: "server-a"), libraryID: "1")

        #expect(identity.stableKey == "plex:server-a:1")
        #expect(LibraryIdentity(stableKey: "plex:server-a:1") == identity)
        let data = try JSONEncoder().encode([identity])
        #expect(String(decoding: data, as: UTF8.self) == #"["plex:server-a:1"]"#)
        #expect(try JSONDecoder().decode([LibraryIdentity].self, from: data) == [identity])
    }

    @Test func `library ids may contain separators`() {
        let identity = LibraryIdentity(stableKey: "jellyfin:server-b:abc:def")

        #expect(identity?.server == ServerIdentity(provider: .jellyfin, id: "server-b"))
        #expect(identity?.libraryID == "abc:def")
    }

    @Test func `invalid library keys are rejected`() {
        #expect(LibraryIdentity(stableKey: "plex:server-a") == nil)
        #expect(LibraryIdentity(stableKey: "emby:server-a:1") == nil)
        #expect(LibraryIdentity(stableKey: "plex::1") == nil)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode([LibraryIdentity].self, from: Data(#"["nope"]"#.utf8))
        }
    }

    @Test func `server identity has a stable text form`() {
        let server = ServerIdentity(provider: .jellyfin, id: "server-b")

        #expect(server.stableKey == "jellyfin:server-b")
        #expect(ServerIdentity(stableKey: "jellyfin:server-b") == server)
        #expect(ServerIdentity(stableKey: "jellyfin") == nil)
    }

    @Test func `libraries persisted without a server still decode`() throws {
        let data = Data(#"{"id":"1","title":"Movies","type":"movie","sectionId":1}"#.utf8)
        let library = try JSONDecoder().decode(Library.self, from: data)
        let server = ServerIdentity(provider: .plex, id: "server-a")

        #expect(library.server == .unassigned)
        #expect(library.assigning(server: server).identity == LibraryIdentity(server: server, libraryID: "1"))
    }
}
