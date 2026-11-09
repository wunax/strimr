import Foundation
@testable import Strimr
import Testing

struct PlexSharedLibraryTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `keeps only the video display types of the shared view`() throws {
        let meta = try Fixtures.decode(PlexSectionItemMeta.self, from: "plex-shared-meta")

        let types = PlexSharedLibrary.videoMeta(meta).type

        #expect(types.map(\.title) == ["All Shared", "Movies", "TV"])
        #expect(types.map(\.key) == [
            "/library/shared/all?type=1,2,3,4",
            "/library/shared/all?type=1",
            "/library/shared/all?type=2,3,4",
        ])
        #expect(types.allSatisfy { $0.sort?.isEmpty == false })
    }

    @Test func `browses the shared view when the library has no section`() {
        let shared = Library(id: "shared", title: "Shared", type: .unknown, isShared: true, server: server)
        let section = Library(id: "4", title: "Movies", type: .movie, sectionId: 4, server: server)
        let unknown = Library(id: "x", title: "X", type: .movie, server: server)

        #expect(shared.plexBrowsePath == "/library/shared/all")
        #expect(section.plexBrowsePath == "/library/sections/4/all")
        #expect(unknown.plexBrowsePath == nil)
    }

    @Test func `decodes libraries saved before the shared flag existed`() throws {
        let json = #"{"id":"1","title":"Movies","type":"movie","sectionId":1}"#
        let library = try JSONDecoder().decode(Library.self, from: Data(json.utf8))

        #expect(library.isShared == false)
    }
}
