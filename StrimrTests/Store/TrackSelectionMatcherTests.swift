@testable import Strimr
import Testing

struct TrackSelectionMatcherTests {
    // MARK: - Audio

    @Test func `audio prefers exact stream index`() {
        let tracks = [
            track(1, language: "eng", codec: "aac"),
            track(2, language: "fra", codec: "ac3"),
        ]
        let preference = audioPreference(streamIndex: 2, language: "eng")

        #expect(bestAudio(preference, tracks)?.id == 2)
    }

    @Test func `audio falls back to attributes when stream index is stale`() {
        let tracks = [
            track(1, language: "eng", codec: "aac"),
            track(2, language: "fra", codec: "ac3"),
        ]
        let preference = audioPreference(streamIndex: 9, language: "fra")

        #expect(bestAudio(preference, tracks)?.id == 2)
    }

    @Test func `audio without preference returns nil`() {
        let tracks = [track(1, language: "eng", codec: "aac")]

        #expect(bestAudio(.serverDefault, tracks) == nil)
    }

    @Test func `audio never leaves preferred language`() {
        let tracks = [
            track(1, language: "eng", title: "Commentary", codec: "aac"),
            track(2, language: "fra", title: "Main", codec: "eac3"),
        ]
        let preference = audioPreference(language: "eng", title: "Main", codec: "eac3")

        #expect(bestAudio(preference, tracks)?.id == 1)
    }

    @Test func `audio missing language returns nil`() {
        let tracks = [track(1, language: "eng", codec: "aac")]
        let preference = audioPreference(language: "jpn")

        #expect(bestAudio(preference, tracks) == nil)
    }

    @Test func `audio uses title then codec within language`() {
        let tracks = [
            track(1, language: "eng", title: "Stereo", codec: "aac"),
            track(2, language: "eng", title: "Surround", codec: "aac"),
            track(3, language: "eng", title: "Atmos", codec: "truehd"),
        ]

        #expect(bestAudio(audioPreference(language: "eng", title: "Surround"), tracks)?.id == 2)
        #expect(bestAudio(audioPreference(language: "eng", codec: "truehd"), tracks)?.id == 3)
    }

    @Test func `audio matches title against display title`() {
        let tracks = [
            track(1, language: "eng", codec: "aac"),
            track(2, language: "eng", displayTitle: "English - Dolby Digital 5.1", codec: "ac3"),
        ]
        let preference = audioPreference(language: "eng", title: "English - Dolby Digital 5.1")

        #expect(bestAudio(preference, tracks)?.id == 2)
    }

    @Test func `audio comparison ignores case and whitespace`() {
        let tracks = [
            track(1, language: "fra", codec: "aac"),
            track(2, language: "eng", codec: "aac"),
        ]
        let preference = audioPreference(language: "  ENG ")

        #expect(bestAudio(preference, tracks)?.id == 2)
    }

    // MARK: - Subtitles

    @Test(arguments: [MediaSubtitlePreference.serverDefault, .off])
    func `subtitle without track preference returns nil`(preference: MediaSubtitlePreference) {
        let tracks = [track(1, language: "eng", codec: "srt")]

        #expect(bestSubtitle(preference, tracks) == nil)
    }

    @Test func `subtitle prefers exact stream index`() {
        let tracks = [
            track(1, language: "eng", codec: "srt"),
            track(2, language: "eng", codec: "ass"),
        ]
        let preference = subtitlePreference(streamIndex: 2, language: "eng", codec: "srt")

        #expect(bestSubtitle(preference, tracks)?.id == 2)
    }

    @Test func `subtitle distinguishes forced tracks`() {
        let tracks = [
            track(1, language: "eng", codec: "srt"),
            track(2, language: "eng", codec: "srt", isForced: true),
        ]

        #expect(bestSubtitle(subtitlePreference(language: "eng", codec: "srt", isForced: true), tracks)?.id == 2)
        #expect(bestSubtitle(subtitlePreference(language: "eng", codec: "srt", isForced: false), tracks)?.id == 1)
    }

    @Test func `subtitle distinguishes hearing impaired tracks`() {
        let tracks = [
            track(1, language: "eng", codec: "srt"),
            track(2, language: "eng", codec: "srt", isHearingImpaired: true),
        ]
        let preference = subtitlePreference(language: "eng", codec: "srt", isHearingImpaired: true)

        #expect(bestSubtitle(preference, tracks)?.id == 2)
    }

    @Test func `subtitle matches by codec without language`() {
        let tracks = [
            track(1, language: "eng", codec: "srt"),
            track(2, language: "fra", codec: "pgs"),
        ]
        let preference = subtitlePreference(codec: "pgs")

        #expect(bestSubtitle(preference, tracks)?.id == 2)
    }

    @Test func `subtitle without attributes returns nil`() {
        let tracks = [track(1, language: "eng", codec: "srt")]
        let preference = subtitlePreference(codec: "")

        #expect(bestSubtitle(preference, tracks) == nil)
    }

    // MARK: - Preference

    @Test func `matching across items drops stream indexes`() {
        let preference = MediaTrackPreference(
            audioStreamIndex: 3,
            audioLanguage: "eng",
            audioTitle: nil,
            audioCodec: "aac",
            audioIsHearingImpaired: nil,
            audioIsCommentary: nil,
            subtitle: subtitlePreference(streamIndex: 5, language: "fra", codec: "srt"),
        )

        let shared = preference.matchingAcrossItems

        #expect(shared.audioStreamIndex == nil)
        #expect(shared.audioLanguage == "eng")
        #expect(shared.subtitle == subtitlePreference(language: "fra", codec: "srt"))
    }

    // MARK: - Helpers

    private func bestAudio(_ preference: MediaTrackPreference, _ tracks: [MediaTrackMetadata]) -> MediaTrackMetadata? {
        TrackSelectionMatcher.bestAudioMatch(
            preference: preference,
            candidates: tracks,
            descriptor: \.trackSelectionMatchDescriptor,
        )
    }

    private func bestSubtitle(
        _ preference: MediaSubtitlePreference,
        _ tracks: [MediaTrackMetadata],
    ) -> MediaTrackMetadata? {
        TrackSelectionMatcher.bestSubtitleMatch(
            preference: preference,
            candidates: tracks,
            descriptor: \.trackSelectionMatchDescriptor,
        )
    }

    private func track(
        _ index: Int,
        language: String?,
        title: String? = nil,
        displayTitle: String? = nil,
        codec: String,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
    ) -> MediaTrackMetadata {
        MediaTrackMetadata(
            id: index,
            sourceIndex: index,
            codec: codec,
            title: title,
            displayTitle: displayTitle ?? title ?? language ?? codec,
            language: language,
            isDefault: false,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
        )
    }

    private func audioPreference(
        streamIndex: Int? = nil,
        language: String? = nil,
        title: String? = nil,
        codec: String? = nil,
    ) -> MediaTrackPreference {
        MediaTrackPreference(
            audioStreamIndex: streamIndex,
            audioLanguage: language,
            audioTitle: title,
            audioCodec: codec,
            audioIsHearingImpaired: nil,
            audioIsCommentary: nil,
            subtitle: .serverDefault,
        )
    }

    private func subtitlePreference(
        streamIndex: Int? = nil,
        language: String? = nil,
        title: String? = nil,
        codec: String,
        isForced: Bool = false,
        isHearingImpaired: Bool? = nil,
    ) -> MediaSubtitlePreference {
        .track(
            streamIndex: streamIndex,
            language: language,
            title: title,
            codec: codec,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
        )
    }
}
