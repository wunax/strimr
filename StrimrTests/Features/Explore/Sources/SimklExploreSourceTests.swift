import Foundation
@testable import Strimr
import Testing

@MainActor
struct SimklExploreSourceTests {
    @Test func `Plan to Watch maps movies, shows and anime`() throws {
        let items = try SimklExploreSource.watchlistItems(Fixtures.data("simkl-plantowatch"))

        #expect(items.map(\.title) == ["Sample Movie", "Sample Show", "Sample Anime Film"])
        #expect(items.map(\.kind) == [.movie, .show, .movie])
        let movie = try #require(items.first)
        #expect(movie.sourceID == "7001")
        #expect(movie.externalIDs == ExternalIDs(imdb: "tt0000001", tmdb: "2001"))
        #expect(movie.posterURL?.absoluteString == "https://simkl.in/posters/00/000000000000000_m.webp")
        #expect(items[1].externalIDs == ExternalIDs(tmdb: "5001", tvdb: "4001"))
    }

    @Test func `an empty Plan to Watch comes back as null`() throws {
        #expect(try SimklExploreSource.watchlistItems(Data("null".utf8)).isEmpty)
    }

    @Test func `trending lists read the CDN ids and release dates`() throws {
        let items = try SimklExploreSource.trending(Fixtures.data("simkl-trending-movies"), kind: .movie)

        let movie = try #require(items.first)
        #expect(items.count == 1)
        #expect(movie.sourceID == "7101")
        #expect(movie.year == 2024)
        #expect(movie.backdropURL?.absoluteString == "https://simkl.in/fanart/22/222222222222222_medium.webp")
    }

    @Test func `a title only leaves the history when it is still planned`() {
        let target = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(tmdb: "2001"))
        let planned = ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs(imdb: "tt1", tmdb: "2001")).keys

        #expect(SimklExploreSource.isPlanned(target, keys: planned))
        #expect(!SimklExploreSource.isPlanned(target, keys: []))
    }

    @Test func `adding targets Plan to Watch and removing sends the ids alone`() throws {
        let target = ExploreWatchlistTarget(kind: .show, externalIDs: ExternalIDs(tvdb: "30"), sourceID: "40")

        let added = try #require(SimklExploreSource.addBody(target)["shows"] as? [[String: Any]])
        #expect(added.first?["to"] as? String == "plantowatch")
        #expect((added.first?["ids"] as? [String: Any])?["simkl"] as? Int == 40)

        let removed = try #require(SimklExploreSource.removeBody(target)["shows"] as? [[String: Any]])
        #expect(removed.first?["to"] == nil)
        #expect((removed.first?["ids"] as? [String: Any])?["tvdb"] as? String == "30")
    }
}
