@testable import Strimr
import Testing

struct PlaybackStartOptionsTests {
    private let remembered = MediaTrackPreference(
        audioStreamIndex: 3,
        audioLanguage: "eng",
        audioTitle: "Surround",
        audioCodec: "eac3",
        audioIsHearingImpaired: nil,
        audioIsCommentary: nil,
        subtitle: .track(
            streamIndex: 5,
            language: "fra",
            title: nil,
            codec: "srt",
            isForced: false,
            isHearingImpaired: nil,
        ),
    )

    @Test func `without languages the remembered tracks stay`() {
        let options = PlaybackStartOptions(offset: 60)

        #expect(options.trackPreference(over: remembered) == remembered)
        #expect(options.trackPreference(over: nil) == nil)
    }

    @Test func `a link language replaces the remembered track of its kind only`() throws {
        let preference = try #require(PlaybackStartOptions(audioLanguage: "ja").trackPreference(over: remembered))

        #expect(preference.audioStreamIndex == nil)
        #expect(preference.audioLanguage == "ja")
        #expect(preference.audioTitle == nil)
        #expect(preference.audioCodec == nil)
        #expect(preference.audioIsCommentary == false)
        #expect(preference.subtitle == remembered.subtitle)
    }

    @Test func `subtitles turn off or ask for a regular track`() {
        #expect(PlaybackStartOptions(subtitles: .off).trackPreference(over: remembered)?.subtitle == .off)

        let preference = PlaybackStartOptions(subtitles: .language("en")).trackPreference(over: nil)
        #expect(preference?.audioLanguage == nil)
        #expect(preference?.subtitle == .track(
            streamIndex: nil,
            language: "en",
            title: nil,
            codec: "",
            isForced: false,
            isHearingImpaired: false,
        ))
    }
}
