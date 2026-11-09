import Foundation
@testable import Strimr
import Testing

struct PlexChapterTests {
    @Test func `decodes chapters of an item shared individually, which have no filter`() throws {
        let response = try Fixtures.decode(PlexItemMediaContainer.self, from: "plex-shared-episode")
        let item = try #require(response.mediaContainer.metadata?.first)

        #expect(item.chapters?.count == 5)
        #expect(item.chapters?.allSatisfy(\.isValid) == true)
    }
}
