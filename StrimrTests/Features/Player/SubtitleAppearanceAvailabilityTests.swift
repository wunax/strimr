@testable import Strimr
import Testing

struct SubtitleAppearanceAvailabilityTests {
    @Test func `text subtitles and no subtitles can be fully customized`() {
        for codec in ["subrip", "ass", nil] {
            let availability = SubtitleAppearanceAvailability(
                burnsSubtitles: false,
                usesStyledRenderer: false,
                codec: codec,
            )

            #expect(availability == .available)
            #expect(availability.allowsTextStyling)
            #expect(availability.samplePreviewText != nil)
        }
    }

    @Test func `bitmap subtitles stay available without text styling or sample`() {
        for codec in ["hdmv_pgs_subtitle", "dvd_subtitle", "dvb_subtitle"] {
            let availability = SubtitleAppearanceAvailability(
                burnsSubtitles: false,
                usesStyledRenderer: false,
                codec: codec,
            )

            #expect(availability == .bitmap)
            #expect(availability.isAvailable)
            #expect(!availability.allowsTextStyling)
            #expect(availability.samplePreviewText == nil)
        }
    }

    @Test func `styled ASS rendering makes the settings unavailable`() {
        let availability = SubtitleAppearanceAvailability(
            burnsSubtitles: false,
            usesStyledRenderer: true,
            codec: "ass",
        )

        #expect(availability == .styledASS)
        #expect(!availability.isAvailable)
        #expect(availability.message != nil)
    }

    @Test func `burned in subtitles take precedence over the track codec`() {
        let availability = SubtitleAppearanceAvailability(
            burnsSubtitles: true,
            usesStyledRenderer: false,
            codec: "hdmv_pgs_subtitle",
        )

        #expect(availability == .burnedIn)
        #expect(!availability.isAvailable)
    }
}
