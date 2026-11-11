import Foundation
@testable import Strimr
import Testing

struct PlexSubtitleSearchResultTests {
    private func decodeResults() throws -> [PlexSubtitleSearchResult] {
        try Fixtures.decode(PlexSubtitleSearchResponse.self, from: "plex-subtitle-search").mediaContainer.streams ?? []
    }

    @Test func `decodes a score sent as a number or a string`() throws {
        let results = try decodeResults()

        #expect(results.first { $0.id == 101 }?.score == 92)
        #expect(results.first { $0.id == 102 }?.score == 87.5)
    }

    @Test func `decodes lenient ids and flags`() throws {
        let result = try #require(try decodeResults().first { $0.id == 102 })

        #expect(result.forced == true)
        #expect(result.hearingImpaired == false)
    }

    @Test func `falls back to the codec when the display title is missing`() throws {
        let result = try #require(try decodeResults().first { $0.id == 103 })

        #expect(result.score == nil)
        #expect(result.displayTitle == "ASS")
    }

    @Test func `skips a result without an id and keeps the others`() throws {
        #expect(try decodeResults().map(\.id) == [101, 102, 103])
    }
}
