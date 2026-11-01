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
        var removedFromContinueWatching: [String] = []
        var changes = 0
        var refreshed: [String] = []
        var analyzed: [String] = []
        var updatesStarted: [String] = []
    }

    private func makeActions(
        supportsFavorites: Bool = true,
        supportsContinueWatchingRemoval: Bool = true,
        calls: Calls = Calls(),
        error: Error? = nil,
        canManageLibrary: Bool = false,
        supportsAnalyze: Bool = true,
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
            removeFromContinueWatching: supportsContinueWatchingRemoval ? { id in
                calls.removedFromContinueWatching.append(id)
                if let error {
                    throw error
                }
            } : nil,
            didChange: { calls.changes += 1 },
            management: canManageLibrary
                ? MediaQuickActions.Management(
                    supportsAnalyze: supportsAnalyze,
                    refreshMetadata: { id in
                        calls.refreshed.append(id)
                        if let error {
                            throw error
                        }
                    },
                    analyze: { id in
                        calls.analyzed.append(id)
                        if let error {
                            throw error
                        }
                    },
                    updateStarted: { calls.updatesStarted.append($0) },
                )
                : nil,
        )
    }

    @Test func `manage submenu ends the menu of library managers when the server is reachable`() {
        let actions = makeActions(canManageLibrary: true)

        #expect(actions.menuActions(for: makeMedia(type: .movie), canDownload: false, canManage: true)
            == [.play, .markWatched, .addFavorite, .manage])
        #expect(!actions.menuActions(for: makeMedia(type: .movie), canDownload: false, canManage: false)
            .contains(.manage))
        #expect(!makeActions().menuActions(for: makeMedia(type: .movie), canDownload: false, canManage: true)
            .contains(.manage))
    }

    @Test func `manage submenu is absent for clips`() {
        let actions = makeActions(canManageLibrary: true)

        #expect(actions.manageActions(for: makeMedia(type: .clip)).isEmpty)
        #expect(!actions.menuActions(for: makeMedia(type: .clip), canDownload: false, canManage: true)
            .contains(.manage))
    }

    @Test func `manage entries follow the server support`() {
        for type in [MediaKind.movie, .series, .season, .episode] {
            #expect(makeActions(canManageLibrary: true).manageActions(for: makeMedia(type: type))
                == [.refreshMetadata, .analyze])
            #expect(makeActions(canManageLibrary: true, supportsAnalyze: false)
                .manageActions(for: makeMedia(type: type)) == [.refreshMetadata])
        }
        #expect(makeActions().manageActions(for: makeMedia(type: .movie)).isEmpty)
    }

    @Test func `refresh and analyze call the server and announce the background update`() async {
        let calls = Calls()
        let actions = makeActions(calls: calls, canManageLibrary: true)

        #expect(await actions.refreshMetadata(makeMedia(type: .series)) == .succeeded)
        #expect(await actions.analyze(makeMedia(type: .movie)) == .succeeded)

        #expect(calls.refreshed == ["item"])
        #expect(calls.analyzed == ["item"])
        #expect(calls.updatesStarted == ["item", "item"])
        #expect(calls.changes == 0)
    }

    @Test func `analyze is skipped when the server does not support it`() async {
        let calls = Calls()
        let outcome = await makeActions(calls: calls, canManageLibrary: true, supportsAnalyze: false)
            .analyze(makeMedia(type: .movie))

        #expect(outcome == .cancelled)
        #expect(calls.analyzed.isEmpty)
    }

    @Test func `refresh is skipped without the right to manage the library`() async {
        let calls = Calls()
        let outcome = await makeActions(calls: calls).refreshMetadata(makeMedia(type: .movie))

        #expect(outcome == .cancelled)
        #expect(calls.refreshed.isEmpty)
    }

    @Test func `server refusal explains the lost right and announces no update`() async {
        let plexCalls = Calls()
        let plex = await makeActions(
            calls: plexCalls,
            error: PlexAPIError.requestFailed(statusCode: 403),
            canManageLibrary: true,
        ).refreshMetadata(makeMedia(type: .movie))
        let jellyfin = await makeActions(error: JellyfinAPIError.permissionDenied, canManageLibrary: true)
            .refreshMetadata(makeMedia(type: .movie))

        let message = String(localized: "media.manage.error.forbidden")
        #expect(plex == .failed(message: message))
        #expect(jellyfin == .failed(message: message))
        #expect(plexCalls.updatesStarted.isEmpty)
    }

    @Test func `management failures carry the server message`() async {
        let outcome = await makeActions(error: Failure(), canManageLibrary: true).analyze(makeMedia(type: .movie))

        #expect(outcome == .failed(message: "Server said no"))
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

    @Test func `details lead the menu of playable items only when offered`() {
        let actions = makeActions()

        #expect(actions.menuActions(for: makeMedia(type: .movie), canDownload: false, offersDetails: true)
            == [.showDetails, .play, .markWatched, .addFavorite])
        #expect(actions.menuActions(for: makeMedia(type: .episode), canDownload: false, offersDetails: true)
            .first == .showDetails)
        #expect(actions.menuActions(for: makeMedia(type: .clip), canDownload: false, offersDetails: true)
            == [.showDetails, .play])
        #expect(!actions.menuActions(for: makeMedia(type: .season), canDownload: false, offersDetails: true)
            .contains(.showDetails))
        #expect(!actions.menuActions(for: makeMedia(type: .movie), canDownload: false).contains(.showDetails))
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

    @Test func `continue watching cards end with the removal`() {
        let actions = makeActions().menuActions(
            for: makeMedia(type: .episode, viewOffset: 600),
            canDownload: false,
            isInContinueWatching: true,
        )

        #expect(actions.last == .removeFromContinueWatching)
    }

    @Test func `removal is only offered in continue watching, on servers that support it`() {
        let movie = makeMedia(type: .movie, viewOffset: 600)

        #expect(!makeActions().menuActions(for: movie, canDownload: false)
            .contains(.removeFromContinueWatching))
        #expect(!makeActions(supportsContinueWatchingRemoval: false)
            .menuActions(for: movie, canDownload: false, isInContinueWatching: true)
            .contains(.removeFromContinueWatching))
    }

    @Test func `removal calls the home service with the item id and reports a change`() async {
        let calls = Calls()

        let outcome = await makeActions(calls: calls).removeFromContinueWatching(makeMedia(type: .episode))

        #expect(outcome == .succeeded)
        #expect(calls.removedFromContinueWatching == ["item"])
        #expect(calls.changes == 1)
    }

    @Test func `removal is skipped when unsupported`() async {
        let calls = Calls()

        let outcome = await makeActions(supportsContinueWatchingRemoval: false, calls: calls)
            .removeFromContinueWatching(makeMedia(type: .movie))

        #expect(outcome == .cancelled)
        #expect(calls.changes == 0)
    }

    @Test func `failures carry the server message`() async {
        let outcome = await makeActions(error: Failure()).setPlayed(false, for: makeMedia(type: .movie))

        #expect(outcome == .failed(message: "Server said no"))
    }

    @Test func `cancellation is not a failure`() async {
        let outcome = await makeActions(error: CancellationError()).setPlayed(true, for: makeMedia(type: .movie))

        #expect(outcome == .cancelled)
    }

    @Test func `successful watched and favorite actions report a change`() async {
        let calls = Calls()
        let actions = makeActions(calls: calls)

        _ = await actions.setPlayed(true, for: makeMedia(type: .episode))
        _ = await actions.setFavorite(true, for: makeMedia(type: .episode))

        #expect(calls.changes == 2)
    }

    @Test func `failed or skipped actions report no change`() async {
        let calls = Calls()

        _ = await makeActions(calls: calls, error: Failure()).setPlayed(true, for: makeMedia(type: .movie))
        _ = await makeActions(supportsFavorites: false, calls: calls).setFavorite(true, for: makeMedia(type: .movie))

        #expect(calls.changes == 0)
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
