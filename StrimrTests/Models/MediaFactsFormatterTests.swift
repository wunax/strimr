import Foundation
@testable import Strimr
import Testing

struct MediaFactsFormatterTests {
    @Test func `movie lists year, runtime and two genres`() {
        let media = makeMedia(
            year: 2021,
            duration: 7920,
            genres: ["Drama", "Thriller", "Crime"],
            contentRating: "PG-13",
        )

        #expect(MediaFactsFormatter.facts(for: media) == MediaFacts(
            tokens: ["2021", TimeInterval(7920).mediaDurationText(), "Drama", "Thriller"],
            contentRating: "PG-13",
        ))
    }

    @Test func `edition follows the year`() {
        let media = makeMedia(editionTitle: "Black and White", year: 2026, duration: 2820)

        #expect(MediaFactsFormatter.facts(for: media).tokens == [
            "2026",
            "Black and White",
            TimeInterval(2820).mediaDurationText(),
        ])
    }

    @Test func `regular cut is named standard only when asked`() {
        let media = makeMedia(year: 2026)

        #expect(MediaFactsFormatter.facts(for: media).tokens == ["2026"])
        #expect(MediaFactsFormatter.facts(for: media, namesStandardEdition: true).tokens == [
            "2026",
            String(localized: "media.editions.standard"),
        ])
    }

    @Test func `series with one season`() {
        let media = makeMedia(type: .series, year: 2019, childCount: 1, genres: ["Comedy"])

        #expect(MediaFactsFormatter.facts(for: media).tokens == [
            "2019",
            String(localized: "media.labels.seasonsCount \(1)"),
            "Comedy",
        ])
    }

    @Test func `series with several seasons prefers the loaded season count`() {
        let media = makeMedia(type: .series, year: 2019, childCount: 2)

        #expect(MediaFactsFormatter.facts(for: media).tokens == [
            "2019",
            String(localized: "media.labels.seasonsCount \(2)"),
        ])
        #expect(MediaFactsFormatter.facts(for: media, seasonCount: 5).tokens == [
            "2019",
            String(localized: "media.labels.seasonsCount \(5)"),
        ])
    }

    @Test func `jellyfin child count is not read as a season count`() {
        let media = makeMedia(type: .series, provider: .jellyfin, year: 2019, childCount: 24)

        #expect(MediaFactsFormatter.facts(for: media).tokens == ["2019"])
    }

    @Test func `missing year and genres are omitted`() {
        let media = makeMedia(duration: 3600, contentRating: " ")

        #expect(MediaFactsFormatter.facts(for: media) == MediaFacts(
            tokens: [TimeInterval(3600).mediaDurationText()],
            contentRating: nil,
        ))
        #expect(MediaFactsFormatter.facts(for: makeMedia()).isEmpty)
    }

    @Test func `episode starts with its number`() {
        let media = makeMedia(type: .episode, year: 2020, duration: 2400, parentIndex: 2, index: 7)

        #expect(MediaFactsFormatter.facts(for: media).tokens == [
            String(localized: "media.labels.seasonEpisode \(2) \(7)"),
            "2020",
            TimeInterval(2400).mediaDurationText(),
        ])
    }

    private func makeMedia(
        type: MediaKind = .movie,
        editionTitle: String? = nil,
        provider: MediaProvider = .plex,
        year: Int? = nil,
        duration: TimeInterval? = nil,
        childCount: Int? = nil,
        genres: [String] = [],
        contentRating: String? = nil,
        parentIndex: Int? = nil,
        index: Int? = nil,
    ) -> MediaItem {
        MediaItem(
            id: "item",
            identity: MediaIdentity(server: ServerIdentity(provider: provider, id: "server"), itemID: "item"),
            guid: "guid://item",
            summary: nil,
            title: "Title",
            editionTitle: editionTitle,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: genres,
            year: year,
            duration: duration,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: contentRating,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: childCount,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }
}

struct RemainingTimeFormatterTests {
    private func expected(minutes: Int) -> String {
        let remaining = Duration.seconds(minutes * 60).formatted(.units(
            allowed: [.hours, .minutes],
            width: .abbreviated,
        ))
        return String(localized: "media.labels.remaining \(remaining)")
    }

    @Test func `no progress means no remaining time`() {
        #expect(RemainingTimeFormatter.text(duration: 3600, viewOffset: nil) == nil)
        #expect(RemainingTimeFormatter.text(duration: 3600, viewOffset: 0) == nil)
        #expect(RemainingTimeFormatter.text(duration: nil, viewOffset: 600) == nil)
    }

    @Test func `less than a minute left shows one minute`() {
        #expect(RemainingTimeFormatter.text(duration: 3600, viewOffset: 3580) == expected(minutes: 1))
    }

    @Test func `rounds to the nearest minute`() {
        #expect(RemainingTimeFormatter.text(duration: 2400, viewOffset: 1020) == expected(minutes: 23))
    }

    @Test func `more than an hour keeps hours and minutes`() {
        #expect(RemainingTimeFormatter.text(duration: 7200, viewOffset: 2880) == expected(minutes: 72))
        #expect(expected(minutes: 72) != expected(minutes: 12))
    }

    @Test func `position past the end has no remaining time`() {
        #expect(RemainingTimeFormatter.text(duration: 3600, viewOffset: 3600) == nil)
        #expect(RemainingTimeFormatter.text(duration: 3600, viewOffset: 4000) == nil)
    }

    @Test func `short text keeps only the time left`() {
        let remaining = Duration.seconds(23 * 60).formatted(.units(allowed: [.hours, .minutes], width: .abbreviated))
        #expect(RemainingTimeFormatter.shortText(duration: 2400, viewOffset: 1020) == remaining)
        #expect(RemainingTimeFormatter.shortText(duration: 2400, viewOffset: 0) == nil)
    }
}
