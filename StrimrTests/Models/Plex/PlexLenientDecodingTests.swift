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

    @Test func `decodes section hidden sent as a number, a string or missing`() throws {
        let json = #"""
        {"MediaContainer": {"size": 3, "Directory": [
            {"agent": "tv.plex.agents.movie", "key": "1", "type": "movie", "title": "Movies", "hidden": 0},
            {"agent": "tv.plex.agents.series", "key": "2", "type": "show", "title": "Shows", "hidden": "1"},
            {"agent": "tv.plex.agents.movie", "key": "3", "type": "movie", "title": "Kids"}
        ]}}
        """#
        let container = try JSONDecoder().decode(PlexSectionMediaContainer.self, from: Data(json.utf8))

        let sections = try #require(container.mediaContainer.directory)
        #expect(sections.map(\.hidden) == [0, 1, nil])
    }
}
