@testable import Strimr
import Testing

struct SkipBackSubtitlesTests {
    private let englishForced = SkipBackSubtitles.Track(id: 1, language: "eng", isForced: true, isCommentary: false)
    private let frenchForced = SkipBackSubtitles.Track(id: 2, language: "fre", isForced: true, isCommentary: false)
    private let english = SkipBackSubtitles.Track(id: 3, language: "en", isForced: false, isCommentary: false)
    private let french = SkipBackSubtitles.Track(id: 4, language: "fra", isForced: false, isCommentary: false)
    private let commentary = SkipBackSubtitles.Track(id: 5, language: "eng", isForced: false, isCommentary: true)

    private var tracks: [SkipBackSubtitles.Track] {
        [englishForced, frenchForced, commentary, english, french]
    }

    @Test func `subtitles off shows the full track in the spoken language`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(from: 100, to: 90, selectedTrackID: nil, tracks: tracks, audioLanguage: "eng")

        #expect(shown == english.id)
    }

    @Test func `forced subtitles switch to the full track in their language`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: frenchForced.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(shown == french.id)
    }

    @Test func `full subtitles already showing are left alone`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: french.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(shown == nil)
        #expect(subtitles.window == nil)
    }

    @Test func `long skips back do not show subtitles`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(from: 100, to: 60, selectedTrackID: nil, tracks: tracks, audioLanguage: "eng")

        #expect(shown == nil)
    }

    @Test func `another language is used when the spoken one has no full track`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: nil,
            tracks: [englishForced, french],
            audioLanguage: "eng",
        )

        #expect(shown == french.id)
    }

    @Test func `nothing happens without a full track`() {
        var subtitles = SkipBackSubtitles()

        let shown = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: nil,
            tracks: [englishForced, commentary],
            audioLanguage: "eng",
        )

        #expect(shown == nil)
        #expect(subtitles.window == nil)
    }

    @Test func `previous state comes back once playback passes the skip point`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: frenchForced.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(subtitles.observe(position: 100.2) == nil)
        #expect(subtitles.observe(position: 90) == nil)
        #expect(subtitles.observe(position: 99.9) == nil)
        #expect(subtitles.observe(position: 100.1) == .init(trackID: frenchForced.id))
        #expect(subtitles.window == nil)
    }

    @Test func `previous state comes back when playback stops on the skip point`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(from: 100, to: 90, selectedTrackID: nil, tracks: tracks, audioLanguage: "eng")
        _ = subtitles.observe(position: 90)

        #expect(subtitles.observe(position: 100) == .init(trackID: nil))
    }

    @Test func `skipping forward to the skip point restores the previous state`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: frenchForced.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(subtitles.skipForward(to: 95) == nil)
        #expect(subtitles.skipForward(to: 100) == .init(trackID: frenchForced.id))
        #expect(subtitles.window == nil)
    }

    @Test func `skipping back again extends the window`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(from: 100, to: 90, selectedTrackID: nil, tracks: tracks, audioLanguage: "eng")
        _ = subtitles.observe(position: 90)

        let shown = subtitles.skipBack(
            from: 95,
            to: 85,
            selectedTrackID: english.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(shown == nil)
        #expect(subtitles.observe(position: 100.1) == .init(trackID: nil))
    }

    @Test func `skip back beyond the limit keeps the original window`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(from: 100, to: 90, selectedTrackID: nil, tracks: tracks, audioLanguage: "eng")

        _ = subtitles.skipBack(from: 90, to: 60, selectedTrackID: english.id, tracks: tracks, audioLanguage: "eng")

        #expect(subtitles.window?.returnPosition == 100)
    }

    @Test func `user track stays the one picked before the window`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: frenchForced.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(subtitles.userTrackID(displayedTrackID: french.id) == frenchForced.id)
        subtitles.cancel()
        #expect(subtitles.userTrackID(displayedTrackID: french.id) == french.id)
    }

    @Test func `ending the window restores the previous track`() {
        var subtitles = SkipBackSubtitles()
        _ = subtitles.skipBack(
            from: 100,
            to: 90,
            selectedTrackID: frenchForced.id,
            tracks: tracks,
            audioLanguage: "eng",
        )

        #expect(subtitles.end() == .init(trackID: frenchForced.id))
        #expect(subtitles.end() == nil)
    }

    @Test func `language codes are normalized`() {
        #expect(SkipBackSubtitles.normalizedLanguage("fre") == "fr")
        #expect(SkipBackSubtitles.normalizedLanguage("fra") == "fr")
        #expect(SkipBackSubtitles.normalizedLanguage("eng") == "en")
        #expect(SkipBackSubtitles.normalizedLanguage("und") == nil)
        #expect(SkipBackSubtitles.normalizedLanguage(" ") == nil)
    }
}
