import Foundation
@testable import Strimr
import Testing

@MainActor
struct MediaQuickActionsTests {
    private struct Failure: LocalizedError {
        var errorDescription: String? {
            "Server said no"
        }
    }

    private final class Calls {
        var played: [(Bool, String)] = []
        var favorites: [(Bool, String)] = []
    }

    private func makeActions(
        supportsFavorites: Bool = true,
        calls: Calls = Calls(),
        error: Error? = nil,
    ) -> MediaQuickActions {
        MediaQuickActions(
            supportsFavorites: supportsFavorites,
            setPlayed: { played, id in
                calls.played.append((played, id))
                if let error {
                    throw error
                }
            },
            setFavorite: { favorite, media in
                calls.favorites.append((favorite, media.id))
                if let error {
                    throw error
                }
            },
        )
    }

    @Test func `unwatched movie offers play, watched and favorite`() {
        let actions = makeActions().menuActions(for: makeMedia(type: .movie), canDownload: true)

        #expect(actions == [.play, .markWatched, .addFavorite, .download])
    }

    @Test func `movie in progress offers resume, play from start and both watch actions`() {
        let actions = makeActions().menuActions(for: makeMedia(type: .movie, viewOffset: 600), canDownload: false)

        #expect(actions == [.resume, .playFromStart, .markWatched, .markUnwatched, .addFavorite])
    }

    @Test func `watched favorite episode offers the reverse actions and its series and season`() {
        let episode = makeMedia(
            type: .episode,
            isPlayed: true,
            isFavorite: true,
            parentRatingKey: "season",
            grandparentRatingKey: "series",
        )

        #expect(makeActions().menuActions(for: episode, canDownload: false) == [
            .play, .markUnwatched, .removeFavorite, .goToSeries, .goToSeason,
        ])
    }

    @Test func `season leads to its series and has no play entry`() {
        let season = makeMedia(type: .season, parentRatingKey: "series")

        #expect(makeActions().menuActions(for: season, canDownload: true) == [
            .markWatched, .addFavorite, .goToSeries, .download,
        ])
    }

    @Test func `favorites are hidden when the server does not support them`() {
        let actions = makeActions(supportsFavorites: false).menuActions(
            for: makeMedia(type: .series),
            canDownload: true,
        )

        #expect(actions == [.markWatched])
    }

    @Test func `movies and episodes can be added to a playlist, seasons cannot`() {
        let actions = makeActions()

        #expect(actions.menuActions(for: makeMedia(type: .movie), canDownload: false, canAddToPlaylist: true)
            == [.play, .markWatched, .addFavorite, .addToPlaylist])
        #expect(actions.menuActions(for: makeMedia(type: .episode), canDownload: false, canAddToPlaylist: true)
            .contains(.addToPlaylist))
        #expect(!actions.menuActions(for: makeMedia(type: .season), canDownload: false, canAddToPlaylist: true)
            .contains(.addToPlaylist))
        #expect(!actions.menuActions(for: makeMedia(type: .movie), canDownload: false).contains(.addToPlaylist))
    }

    @Test func `clips cannot be marked or favorited`() {
        #expect(makeActions().menuActions(for: makeMedia(type: .clip), canDownload: true) == [.play])
    }

    @Test func `watched action calls the detail service with the item id`() async {
        let calls = Calls()
        let outcome = await makeActions(calls: calls).setPlayed(true, for: makeMedia(type: .movie))

        #expect(outcome == .succeeded)
        #expect(calls.played.map(\.0) == [true])
        #expect(calls.played.map(\.1) == ["item"])
    }

    @Test func `favorite action calls the favorites service`() async {
        let calls = Calls()
        let outcome = await makeActions(calls: calls).setFavorite(false, for: makeMedia(type: .episode))

        #expect(outcome == .succeeded)
        #expect(calls.favorites.map(\.0) == [false])
    }

    @Test func `favorite action is skipped when unsupported`() async {
        let calls = Calls()
        let outcome = await makeActions(supportsFavorites: false, calls: calls)
            .setFavorite(true, for: makeMedia(type: .movie))

        #expect(outcome == .cancelled)
        #expect(calls.favorites.isEmpty)
    }

    @Test func `failures carry the server message`() async {
        let outcome = await makeActions(error: Failure()).setPlayed(false, for: makeMedia(type: .movie))

        #expect(outcome == .failed(message: "Server said no"))
    }

    @Test func `cancellation is not a failure`() async {
        let outcome = await makeActions(error: CancellationError()).setPlayed(true, for: makeMedia(type: .movie))

        #expect(outcome == .cancelled)
    }

    private func makeMedia(
        type: MediaKind,
        viewOffset: TimeInterval? = nil,
        isPlayed: Bool = false,
        isFavorite: Bool = false,
        parentRatingKey: String? = nil,
        grandparentRatingKey: String? = nil,
    ) -> MediaItem {
        MediaItem(
            id: "item",
            guid: "plex://item",
            summary: nil,
            title: "Title",
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: [],
            year: nil,
            duration: 3600,
            videoResolution: nil,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: viewOffset,
            viewCount: isPlayed ? 1 : 0,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            watchState: MediaWatchState(
                isPlayed: isPlayed,
                playCount: isPlayed ? 1 : 0,
                resumePosition: viewOffset,
                unplayedItemCount: nil,
                isFavorite: isFavorite,
            ),
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
        )
    }
}
