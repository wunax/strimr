import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackSelectionCoordinatorTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")
    private let defaults = TestDefaults.make()
    private let settings: SettingsManager
    private let coordinator: TrackSelectionCoordinator

    init() {
        settings = SettingsManager(userDefaults: defaults)
        coordinator = TrackSelectionCoordinator(
            store: TrackSelectionStore(userDefaults: defaults),
            settingsManager: settings,
        )
    }

    @Test func `a remembered audio track is picked again for the same movie`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")

        let resolution = resolve(movie, audio: [track(1, language: "eng"), track(2, language: "fra")])

        #expect(resolution?.audioTrackID == 2)
    }

    @Test func `a remembered choice is kept per account`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")

        #expect(coordinator.preference(for: movie, server: server, accountIdentifier: "user-2") == nil)
    }

    @Test func `episodes of a series share their choice by language, not by stream`() {
        coordinator.rememberAudio(
            track(2, language: "fra"),
            for: episode("s1e1"),
            server: server,
            accountIdentifier: "user-1",
        )

        let resolution = resolve(episode("s1e2"), audio: [track(5, language: "eng"), track(7, language: "fra")])

        #expect(resolution?.audioTrackID == 7)
    }

    @Test func `turning subtitles off is remembered`() {
        let movie = movie("movie-1")
        coordinator.rememberSubtitle(
            nil as MediaTrackMetadata?,
            for: movie,
            server: server,
            accountIdentifier: "user-1",
        )

        let resolution = resolve(movie, subtitles: [track(3, language: "eng")])

        #expect(resolution?.subtitleIsOff == true)
        #expect(resolution?.subtitleTrackID == nil)
    }

    @Test func `remembering a subtitle keeps the audio choice`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")
        coordinator.rememberSubtitle(track(4, language: "eng"), for: movie, server: server, accountIdentifier: "user-1")

        let resolution = resolve(
            movie,
            audio: [track(1, language: "eng"), track(2, language: "fra")],
            subtitles: [track(4, language: "eng")],
        )

        #expect(resolution?.audioTrackID == 2)
        #expect(resolution?.subtitleTrackID == 4)
    }

    @Test func `nothing is remembered when the setting is off`() {
        settings.setRememberTrackSelections(false)
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")
        settings.setRememberTrackSelections(true)

        #expect(coordinator.preference(for: movie, server: server, accountIdentifier: "user-1") == nil)
    }

    @Test func `a remembered choice is ignored while the setting is off`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")

        settings.setRememberTrackSelections(false)

        #expect(resolve(movie, audio: [track(2, language: "fra")]) == nil)
    }

    @Test func `resetting forgets the choice`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")

        coordinator.reset(for: movie, server: server, accountIdentifier: "user-1")

        #expect(coordinator.preference(for: movie, server: server, accountIdentifier: "user-1") == nil)
    }

    @Test func `an episode without a series has nothing to remember`() {
        let orphan = MediaItem.make(id: "episode-1", server: server, type: .episode)
        coordinator.rememberAudio(track(2, language: "fra"), for: orphan, server: server, accountIdentifier: "user-1")

        #expect(coordinator.preference(for: orphan, server: server, accountIdentifier: "user-1") == nil)
    }

    @Test func `choices survive a relaunch`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(track(2, language: "fra"), for: movie, server: server, accountIdentifier: "user-1")

        let relaunched = TrackSelectionCoordinator(
            store: TrackSelectionStore(userDefaults: defaults),
            settingsManager: SettingsManager(userDefaults: defaults),
        )

        #expect(relaunched.preference(for: movie, server: server, accountIdentifier: "user-1")?.audioLanguage == "fra")
    }

    @Test func `a blank track title is not remembered`() {
        let movie = movie("movie-1")
        coordinator.rememberAudio(
            track(2, language: "fra", title: "  "),
            for: movie,
            server: server,
            accountIdentifier: "user-1",
        )

        #expect(coordinator.preference(for: movie, server: server, accountIdentifier: "user-1")?.audioTitle == nil)
    }

    // MARK: - Helpers

    private func resolve(
        _ media: MediaItem,
        audio: [MediaTrackMetadata] = [],
        subtitles: [MediaTrackMetadata] = [],
    ) -> TrackSelectionResolution? {
        coordinator.resolvedSelection(
            for: media,
            audioTracks: audio,
            subtitleTracks: subtitles,
            server: server,
            accountIdentifier: "user-1",
        )
    }

    private func movie(_ id: String) -> MediaItem {
        MediaItem.make(id: id, server: server)
    }

    private func episode(_ id: String) -> MediaItem {
        MediaItem.make(id: id, server: server, type: .episode, parentID: "season-1", seriesID: "series-1")
    }

    private func track(_ id: Int, language: String, title: String? = nil, codec: String = "aac") -> MediaTrackMetadata {
        MediaTrackMetadata(
            id: id,
            sourceIndex: id,
            codec: codec,
            title: title,
            displayTitle: language,
            language: language,
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
        )
    }
}
