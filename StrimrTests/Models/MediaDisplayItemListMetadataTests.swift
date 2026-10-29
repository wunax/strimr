import Foundation
@testable import Strimr
import Testing

struct MediaDisplayItemListMetadataTests {
    @Test func `metadata line keeps a stable order`() {
        let media = makeMedia(year: 2019, duration: 7920, contentRating: "PG-13", rating: 7.8)

        #expect(media.listMetadataLine == [
            "2019",
            TimeInterval(7920).mediaDurationText(),
            "PG-13",
            "★ " + 7.8.formatted(.number.precision(.fractionLength(1))),
        ].joined(separator: " • "))
    }

    @Test func `missing metadata values are omitted`() {
        let media = makeMedia(year: nil, duration: 3600, contentRating: "", rating: nil)

        #expect(media.listMetadataLine == TimeInterval(3600).mediaDurationText())
    }

    @Test func `metadata line is nil when nothing is known`() {
        #expect(makeMedia().listMetadataLine == nil)
    }

    @Test func `movie subtitle does not repeat the year`() {
        #expect(makeMedia(year: 2019).listSubtitle == nil)
    }

    @Test func `movie subtitle shows only the edition`() {
        #expect(makeMedia(editionTitle: "Director's Cut", year: 1982).listSubtitle == "Director's Cut")
    }

    @Test func `card captions keep the edition`() {
        let episodeNumber = String(localized: "media.labels.seasonEpisode \(1) \(3)")
        let movie = makeMedia(editionTitle: "Director's Cut", year: 1982)
        let season = makeMedia(type: .season, editionTitle: "Black and White")
        let episode = makeMedia(type: .episode, editionTitle: "Black and White", parentIndex: 1, index: 3)

        #expect(movie.cardSecondaryLabel(remainingTime: nil) == "1982 · Director's Cut")
        #expect(movie.cardSecondaryLabel(remainingTime: "23 min left") == "23 min left · Director's Cut")
        #expect(season.cardSecondaryLabel(remainingTime: nil) == "Title · Black and White")
        #expect(episode.cardSecondaryLabel(remainingTime: nil) == "Title")
        #expect(episode
            .cardTertiaryLabel(remainingTime: "23 min left") == "\(episodeNumber) · Black and White · 23 min left")
        #expect(makeMedia(type: .season).cardSecondaryLabel(remainingTime: nil) == "Title")
    }

    @Test func `season and episode subtitles name the edition`() {
        let season = makeMedia(type: .season, editionTitle: "Black and White")
        let episode = makeMedia(
            type: .episode,
            editionTitle: "Black and White",
            grandparentTitle: "Series",
            parentIndex: 1,
            index: 3,
        )

        #expect(season.listSubtitle == "Black and White")
        #expect(episode.listSubtitle == "Series · " + String(localized: "media.labels.seasonEpisode \(1) \(3)")
            + " · Black and White")
    }

    @Test func `episode subtitle shows the series and episode number`() {
        let media = makeMedia(type: .episode, grandparentTitle: "Series", parentIndex: 1, index: 3)

        #expect(media.listSubtitle == "Series · " + String(localized: "media.labels.seasonEpisode \(1) \(3)"))
        #expect(media.usesWideListArtwork)
    }

    private func makeMedia(
        type: MediaKind = .movie,
        editionTitle: String? = nil,
        year: Int? = nil,
        duration: TimeInterval? = nil,
        contentRating: String? = nil,
        rating: Double? = nil,
        grandparentTitle: String? = nil,
        parentIndex: Int? = nil,
        index: Int? = nil,
    ) -> MediaDisplayItem {
        .playable(MediaItem(
            id: "item",
            guid: "plex://item",
            summary: nil,
            title: "Title",
            editionTitle: editionTitle,
            type: type,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: year,
            duration: duration,
            videoResolution: nil,
            rating: rating,
            ratings: [],
            contentRating: contentRating,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: grandparentTitle,
            parentTitle: nil,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        ))
    }
}
