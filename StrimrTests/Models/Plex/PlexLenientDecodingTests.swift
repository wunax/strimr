import Foundation
@testable import Strimr
import Testing

struct PlexLenientDecodingTests {
    private func decodeCollections(_ metadata: String) throws -> [PlexItem] {
        let json = #"{"MediaContainer": {"size": 2, "Metadata": \#(metadata)}}"#
        let container = try JSONDecoder().decode(PlexItemMediaContainer.self, from: Data(json.utf8))
        return container.mediaContainer.metadata ?? []
    }

    private func collection(ratingKey: String, extra: String = "") -> String {
        #"{"ratingKey": "\#(ratingKey)", "key": "/library/collections/\#(ratingKey)/children", "guid": "collection://\#(ratingKey)", "type": "collection", "title": "Collection \#(ratingKey)"\#(extra)}"#
    }

    @Test func `decodes smart and year range sent with other types`() throws {
        let items =
            try decodeCollections(
                "[\(collection(ratingKey: "1", extra: #", "smart": "1", "minYear": 2001, "maxYear": "2019""#))]",
            )

        let item = try #require(items.first)
        #expect(item.smart?.value == true)
        #expect(item.minYear?.value == "2001")
        #expect(item.maxYear?.value == "2019")
    }

    @Test func `leaves missing and null lenient fields empty`() throws {
        let items = try decodeCollections("[\(collection(ratingKey: "1", extra: #", "smart": null"#))]")

        let item = try #require(items.first)
        #expect(item.smart == nil)
        #expect(item.minYear == nil)
    }

    @Test func `skips the malformed item and keeps the others`() throws {
        let malformed = collection(ratingKey: "2", extra: #", "childCount": {"unexpected": true}"#)
        let items =
            try decodeCollections("[\(collection(ratingKey: "1")), \(malformed), \(collection(ratingKey: "3"))]")

        #expect(items.map(\.ratingKey) == ["1", "3"])
    }

    @Test func `keeps a missing metadata array empty`() throws {
        let json = #"{"MediaContainer": {"size": 0}}"#
        let container = try JSONDecoder().decode(PlexItemMediaContainer.self, from: Data(json.utf8))

        #expect(container.mediaContainer.metadata == nil)
    }
}
