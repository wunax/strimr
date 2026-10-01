@testable import Strimr
import Testing

@MainActor
struct PlayerViewModelTrackPreferenceTests {
    private let tracks = [
        Self.track(id: "11", sourceIndex: 1, kind: .audio, title: "English 5.1", language: "eng", codec: "eac3"),
        Self.track(id: "12", sourceIndex: 2, kind: .audio, title: "Français 5.1", language: "fra", codec: "ac3"),
        Self.track(
            id: "21",
            sourceIndex: 3,
            kind: .subtitle,
            title: "English (Forced)",
            language: "eng",
            codec: "srt",
            isForced: true,
        ),
    ]

    @Test func `describes playing tracks without stream ids`() {
        let preference = PlayerViewModel.sessionTrackPreference(
            tracks: tracks,
            audioSourceIndex: 2,
            subtitleStreamID: 21,
            subtitleIsOff: false,
        )

        #expect(preference.audioStreamIndex == nil)
        #expect(preference.audioLanguage == "fra")
        #expect(preference.audioCodec == "ac3")
        #expect(preference.subtitle == .track(
            streamIndex: nil,
            language: "eng",
            title: "English (Forced)",
            codec: "srt",
            isForced: true,
            isHearingImpaired: false,
        ))
    }

    @Test func `no active subtitle carries over as off`() {
        let preference = PlayerViewModel.sessionTrackPreference(
            tracks: tracks,
            audioSourceIndex: 1,
            subtitleStreamID: nil,
            subtitleIsOff: false,
        )

        #expect(preference.subtitle == .off)
    }

    @Test func `subtitle missing from the plan falls back to server default`() {
        let preference = PlayerViewModel.sessionTrackPreference(
            tracks: tracks,
            audioSourceIndex: 1,
            subtitleStreamID: -1,
            subtitleIsOff: false,
        )

        #expect(preference.subtitle == .serverDefault)
    }

    @Test func `unknown audio leaves the language to the server`() {
        let preference = PlayerViewModel.sessionTrackPreference(
            tracks: tracks,
            audioSourceIndex: 9,
            subtitleStreamID: nil,
            subtitleIsOff: true,
        )

        #expect(preference.audioLanguage == nil)
        #expect(preference.subtitle == .off)
    }

    private static func track(
        id: String,
        sourceIndex: Int,
        kind: PlaybackTrackKind,
        title: String,
        language: String,
        codec: String,
        isForced: Bool = false,
    ) -> PlaybackTrack {
        PlaybackTrack(
            id: id,
            sourceIndex: sourceIndex,
            kind: kind,
            isExternal: false,
            title: title,
            language: language,
            codec: codec,
            isDefault: false,
            isForced: isForced,
            isHearingImpaired: false,
        )
    }
}
