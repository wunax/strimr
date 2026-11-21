import Foundation
@testable import Strimr
import Testing

struct PlexItemDecodingTests {
    private func decodeHubs() throws -> [PlexHub] {
        try Fixtures.decode(PlexHubMediaContainer.self, from: "plex-lookalike-hubs").mediaContainer.hub ?? []
    }

    private func decodeItems() throws -> [PlexItem] {
        try #require(try decodeHubs().first).metadata ?? []
    }

    @Test func `skips a malformed hub and keeps the others`() throws {
        let hubs = try decodeHubs()

        #expect(hubs.map(\.hubIdentifier) == ["home.movies.trending"])
        #expect(hubs.first?.size == 3)
        #expect(hubs.first?.more == true)
    }

    @Test func `skips an item without a rating key and keeps the others`() throws {
        #expect(try decodeItems().map(\.ratingKey) == ["1001", "1002"])
    }

    @Test func `gives an item without a guid a local guid`() throws {
        let items = try decodeItems()

        #expect(items.first { $0.ratingKey == "1001" }?.guid == "local://1001")
        #expect(items.first { $0.ratingKey == "1002" }?.guid == "plex://movie/sample-guid")
    }

    @Test func `decodes numbers sent as strings`() throws {
        let item = try #require(try decodeItems().first { $0.ratingKey == "1001" })

        #expect(item.year == 2021)
        #expect(item.duration == 7_200_000)
        #expect(item.audienceRating == 7.4)
    }

    @Test func `drops invalid secondary entries and keeps the valid ones`() throws {
        let item = try #require(try decodeItems().first { $0.ratingKey == "1001" })

        #expect(item.images?.map(\.type) == ["clearLogo"])
        #expect(item.genres?.map(\.tag) == ["Drama"])
        #expect(item.media?.count == 1)
    }

    @Test func `ignores invalid artwork colors`() throws {
        let item = try #require(try decodeItems().first { $0.ratingKey == "1002" })

        #expect(item.ultraBlurColors == nil)
    }
}
