@testable import Strimr
import Testing

struct MediaTrackMetadataTests {
    @Test func `shows a plex stream name that the display title lacks`() {
        let track = Self.track(title: "VFQ", displayTitle: "Français (EAC3 5.1)")

        #expect(track.secondaryTitle == "VFQ")
        #expect(track.summaryTitle == "VFQ · Français (EAC3 5.1)")
    }

    @Test func `hides a stream name already in the display title`() {
        let lowercased = Self.track(title: "français", displayTitle: "Français (EAC3 5.1)")
        let label = Self.track(title: "SDH", displayTitle: "English SDH")
        let jellyfin = Self.track(title: "VFF", displayTitle: "VFF - French - Dolby Digital+ - 5.1 - Default")

        for track in [lowercased, label, jellyfin] {
            #expect(track.secondaryTitle == nil)
            #expect(track.summaryTitle == track.displayTitle)
        }
    }

    @Test func `ignores missing or blank stream names`() {
        #expect(Self.track(title: nil, displayTitle: "English (AC3 5.1)").secondaryTitle == nil)
        #expect(Self.track(title: "  ", displayTitle: "English (AC3 5.1)").secondaryTitle == nil)
    }

    @Test func `falls back to the stream name without a display title`() {
        #expect(Self.track(title: "Commentary", displayTitle: "").summaryTitle == "Commentary")
    }

    private static func track(title: String?, displayTitle: String) -> MediaTrackMetadata {
        MediaTrackMetadata(
            id: 1,
            sourceIndex: 1,
            codec: "eac3",
            title: title,
            displayTitle: displayTitle,
            language: "fra",
            isDefault: false,
            isForced: false,
            isHearingImpaired: false,
        )
    }
}
