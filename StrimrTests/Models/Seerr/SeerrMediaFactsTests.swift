import Foundation
@testable import Strimr
import Testing

struct SeerrMediaFactsTests {
    @Test func `movie lists year, runtime and two genres`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-movie")

        #expect(MediaFactsFormatter.facts(for: media) == MediaFacts(
            tokens: ["2021", TimeInterval(132 * 60).mediaDurationText(), "Drama", "Thriller"],
        ))
    }

    @Test func `series lists first air year, season count and named genres`() throws {
        let media = try Fixtures.decode(SeerrMedia.self, from: "seerr-tv")

        #expect(media.displayTitle == "Sample Series")
        #expect(MediaFactsFormatter.facts(for: media).tokens == [
            "2019",
            String(localized: "media.labels.seasonsCount \(3)"),
            "Comedy",
        ])
    }

    @Test func `item without dates, runtime or genres has no facts`() {
        let media = SeerrMedia(placeholderID: 1, mediaType: .movie)

        #expect(MediaFactsFormatter.facts(for: media).isEmpty)
    }

    @Test func `rotten tomatoes percentages become tenths and tmdb follows imdb`() throws {
        let ratings = try Fixtures.decode(SeerrMediaRatings.self, from: "seerr-ratings")

        #expect(MediaRating.ratings(from: ratings, voteAverage: 7.4) == [
            MediaRating(source: .rottenTomatoesCritic, value: 9.2),
            MediaRating(source: .rottenTomatoesAudience, value: 8.5),
            MediaRating(source: .imdb, value: 7.8),
            MediaRating(source: .tmdb, value: 7.4),
        ])
    }

    @Test func `missing scores and an empty vote average are left out`() {
        #expect(MediaRating.ratings(from: nil, voteAverage: 0).isEmpty)
    }
}
