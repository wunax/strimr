import Foundation
@testable import Strimr
import Testing

@MainActor
struct TraktExploreSourceTests {
    @Test func `watchlist entries map to items with their ids and images`() throws {
        let items = try TraktExploreSource.entries(Fixtures.data("trakt-watchlist-movies"))

        #expect(items.map(\.title) == ["Sample Movie", "Movie Without Images"])
        let movie = try #require(items.first)
        #expect(movie.source == .trakt)
        #expect(movie.sourceID == "1001")
        #expect(movie.kind == .movie)
        #expect(movie.year == 2020)
        #expect(movie.externalIDs == ExternalIDs(imdb: "tt0000001", tmdb: "2001"))
        #expect(movie.posterURL?.absoluteString == "https://media.example.invalid/images/movies/poster.jpg.webp")
        #expect(movie.backdropURL?.absoluteString == "https://media.example.invalid/images/movies/fanart.jpg.webp")
        #expect(items[1].posterURL == nil)
    }

    @Test func `bare lists take their kind from the row`() throws {
        let items = try TraktExploreSource.media(Fixtures.data("trakt-popular-shows"), kind: .show)

        let show = try #require(items.first)
        #expect(show.kind == .show)
        #expect(show.externalIDs == ExternalIDs(imdb: "tt0000003", tmdb: "5001", tvdb: "4001"))
        #expect(show.posterURL?.absoluteString == "https://media.example.invalid/show-poster.jpg")
        #expect(show.backdropURL?.absoluteString == "https://media.example.invalid/show-thumb.jpg")
    }

    @Test func `watchlist changes send numeric ids under the title's kind`() throws {
        let body = try #require(TraktExploreSource.watchlistBody(ExploreWatchlistTarget(
            kind: .show,
            externalIDs: ExternalIDs(imdb: "tt1", tmdb: "20", tvdb: "30"),
            sourceID: "40",
        )))

        let shows = try #require(body["shows"] as? [[String: Any]])
        let ids = try #require(shows.first?["ids"] as? [String: Any])
        #expect(ids["trakt"] as? Int == 40)
        #expect(ids["imdb"] as? String == "tt1")
        #expect(ids["tmdb"] as? Int == 20)
        #expect(ids["tvdb"] as? Int == 30)
        #expect(body["movies"] == nil)
    }

    @Test func `a title without any id cannot be sent`() {
        #expect(TraktExploreSource.watchlistBody(ExploreWatchlistTarget(kind: .movie, externalIDs: ExternalIDs()))
            == nil)
    }
}
