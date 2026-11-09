import Foundation
@testable import Strimr
import Testing

struct TrackerRequestBodyTests {
    @Test func `trakt converts ids to integers and leaves tvdb out of movies`() throws {
        let item = TrackerItem(kind: .movie, ids: ExternalIDs(imdb: "tt1", tmdb: "42", tvdb: "7"))

        let media = try #require(TraktAPI.media(item))
        let ids = try #require(media["ids"] as? [String: Any])

        #expect(ids["imdb"] as? String == "tt1")
        #expect(ids["tmdb"] as? Int == 42)
        #expect(ids["tvdb"] == nil)
    }

    @Test func `trakt ignores a non numeric id and skips an item left with nothing`() {
        let item = TrackerItem(kind: .episode, ids: ExternalIDs(tmdb: "abc"))

        #expect(TraktAPI.media(item) == nil)
    }

    @Test func `simkl sends every identifier with title and year`() throws {
        let media = try #require(SimklAPI.media(TrackerFixtures.episode(1)))
        let ids = try #require(media["ids"] as? [String: Any])

        #expect(ids["tvdb"] as? String == "303")
        #expect(media["title"] as? String == "Series")
        #expect(media["year"] as? Int == 2019)
    }

    @Test func `an episode scrobble names the series with season and number`() throws {
        let body = try #require(TrackerRequestBody.scrobble(
            item: TrackerFixtures.episode(3, season: 2),
            progress: 12.3456,
            media: TraktAPI.media,
        ))

        #expect(body["progress"] as? Double == 12.35)
        #expect(body["show"] != nil)
        let episode = try #require(body["episode"] as? [String: Any])
        #expect(episode["season"] as? Int == 2)
        #expect(episode["number"] as? Int == 3)
    }

    @Test func `an episode without a number cannot be scrobbled`() {
        let item = TrackerItem(kind: .episode, ids: TrackerFixtures.seriesIDs, season: 1)

        #expect(TrackerRequestBody.scrobble(item: item, progress: 10, media: TraktAPI.media) == nil)
    }

    @Test func `history nests episodes of a series under one show and dates them`() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let body = try #require(TrackerRequestBody.history(
            [
                TrackerHistoryEntry(item: TrackerFixtures.episode(2, season: 2), watchedAt: date),
                TrackerHistoryEntry(item: TrackerFixtures.episode(1, season: 1), watchedAt: date),
                TrackerHistoryEntry(item: TrackerFixtures.movie, watchedAt: nil),
            ],
            media: TraktAPI.media,
        ))

        let shows = try #require(body["shows"] as? [[String: Any]])
        #expect(shows.count == 1)
        let seasons = try #require(shows[0]["seasons"] as? [[String: Any]])
        #expect(seasons.map { $0["number"] as? Int } == [1, 2])
        let episodes = try #require(seasons[0]["episodes"] as? [[String: Any]])
        #expect(episodes[0]["number"] as? Int == 1)
        #expect(episodes[0]["watched_at"] as? String == "2023-11-14T22:13:20Z")

        let movies = try #require(body["movies"] as? [[String: Any]])
        #expect(movies[0]["watched_at"] == nil)
    }

    @Test func `history sends nothing when no item can be addressed`() {
        let item = TrackerItem(kind: .movie, ids: ExternalIDs())

        #expect(TrackerRequestBody.history(
            [TrackerHistoryEntry(item: item, watchedAt: nil)],
            media: TraktAPI.media,
        ) == nil)
    }
}
