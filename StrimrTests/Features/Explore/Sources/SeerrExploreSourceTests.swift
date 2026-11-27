import Foundation
@testable import Strimr
import Testing

@MainActor
struct SeerrExploreSourceTests {
    @Test func `a Seerr title keeps its TMDB id and payload`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie")
        let item = try #require(SeerrExploreSource.item(from: media, kind: nil))

        #expect(item.source == .seerr)
        #expect(item.kind == .movie)
        #expect(item.sourceID == String(media.id))
        #expect(item.tmdbID == media.id)
        #expect(item.seerrMedia?.id == media.id)
    }

    @Test func `a list without types takes the row's kind`() throws {
        var media = try Fixtures.decode(SeerrMedia.self, from: "seerr-tv")
        media.mediaType = nil

        #expect(SeerrExploreSource.item(from: media, kind: .show)?.kind == .show)
        #expect(SeerrExploreSource.item(from: media, kind: nil) == nil)
    }

    @Test func `people are left out`() throws {
        var media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie")
        media.mediaType = .person

        #expect(SeerrExploreSource.item(from: media, kind: .movie) == nil)
    }
}
