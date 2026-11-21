import Foundation
@testable import Strimr
import Testing

struct JellyfinItemListTests {
    @Test func `decodes a bare array`() throws {
        let list = try Fixtures.decode(JellyfinItemList<JellyfinItem>.self, from: "jellyfin-extras")

        #expect(list.items.map(\.id) == ["trailer-1", "extra-1"])
    }

    @Test func `decodes items wrapped in a query result`() throws {
        let list = try Fixtures.decode(JellyfinItemList<JellyfinItem>.self, from: "jellyfin-extras-wrapped")

        #expect(list.items.map(\.id) == ["trailer-1", "extra-1"])
    }

    @Test func `keeps the item error when an array element is malformed`() {
        let json = #"[{ "Id": "trailer-1", "Name": "Example Trailer" }, { "Name": "Missing Id" }]"#

        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(JellyfinItemList<JellyfinItem>.self, from: Data(json.utf8))
        }
    }
}
