@testable import Strimr
import Testing

struct PlaybackSettingsTrackTests {
    @Test func `tells apart audio tracks sharing a display title`() {
        let vff = Self.settingsTrack(name: "VFF", displayTitle: "Français (EAC3 5.1)", codec: "eac3")
        let vfq = Self.settingsTrack(name: "VFQ", displayTitle: "Français (EAC3 5.1)", codec: "eac3")

        #expect(vff.title == vfq.title)
        #expect(vff.subtitle == "VFF")
        #expect(vfq.subtitle == "VFQ")
    }

    @Test func `adds the codec when the display title does not show it`() {
        let track = Self.settingsTrack(name: "Forcés", displayTitle: "Français Forced", codec: "srt")

        #expect(track.subtitle == "Forcés • SRT")
    }

    @Test func `keeps the codec alone for unnamed tracks`() {
        let track = Self.settingsTrack(name: nil, displayTitle: "Français", codec: "pgs")

        #expect(track.subtitle == "PGS")
    }

    private static func settingsTrack(name: String?, displayTitle: String, codec: String) -> PlaybackSettingsTrack {
        let playerTrack = PlayerTrack(
            id: 1,
            ffIndex: 1,
            providerStreamID: 1,
            type: .audio,
            title: displayTitle,
            language: "fra",
            codec: codec,
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
            isCommentary: false,
            isExternal: false,
            isSelected: false,
        )
        let metadata = MediaTrackMetadata(
            id: 1,
            sourceIndex: 1,
            codec: codec,
            title: name,
            displayTitle: displayTitle,
            language: "fra",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
        )
        return PlaybackSettingsTrack(track: playerTrack, metadata: metadata)
    }
}
