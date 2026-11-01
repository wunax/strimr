@testable import Strimr
import Testing

struct PlayerTrackTests {
    private func track(
        _ id: Int,
        _ language: String?,
        isDefault: Bool = false,
        isForced: Bool = false,
        isHearingImpaired: Bool = false,
        isCommentary: Bool = false,
    ) -> PlayerTrack {
        PlayerTrack(
            id: id,
            ffIndex: id,
            providerStreamID: id,
            type: .audio,
            title: nil,
            language: language,
            codec: nil,
            isDefault: isDefault,
            isForced: isForced,
            isHearingImpaired: isHearingImpaired,
            isCommentary: isCommentary,
            isExternal: false,
            isSelected: false,
        )
    }

    @Test func `matches two and three letter codes alike`() {
        let tracks = [track(1, "eng"), track(2, "fre"), track(3, "jpn")]

        #expect(tracks.best(forLanguage: "fr")?.id == 2)
        #expect(tracks.best(forLanguage: "fra")?.id == 2)
        #expect(tracks.best(forLanguage: "FRE")?.id == 2)
        #expect(tracks.best(forLanguage: "ja")?.id == 3)
    }

    @Test func `a missing language gives no track`() {
        #expect([track(1, "eng"), track(2, nil)].best(forLanguage: "de") == nil)
        #expect([PlayerTrack]().best(forLanguage: "en") == nil)
    }

    @Test func `prefers a regular track over commentary, hearing impaired and forced`() {
        let tracks = [
            track(1, "eng", isDefault: true, isCommentary: true),
            track(2, "eng", isDefault: true, isHearingImpaired: true),
            track(3, "eng", isDefault: true, isForced: true),
            track(4, "eng"),
        ]

        #expect(tracks.best(forLanguage: "en")?.id == 4)
    }

    @Test func `prefers the default among regular tracks, then the first`() {
        #expect([track(1, "en"), track(2, "en", isDefault: true)].best(forLanguage: "en")?.id == 2)
        #expect([track(1, "en"), track(2, "en")].best(forLanguage: "en")?.id == 1)
    }

    @Test func `a forced track is still picked when it is the only one`() {
        #expect([track(1, "en", isForced: true)].best(forLanguage: "en")?.id == 1)
    }
}
