import Foundation

/// What the appearance settings can change on the subtitles currently playing.
enum SubtitleAppearanceAvailability: Hashable {
    case available
    /// Bitmap subtitles keep their styling, only their brightness and bottom margin can change.
    case bitmap
    case styledASS
    case burnedIn

    private static let bitmapCodecs: Set<String> = [
        "hdmv_pgs_subtitle", "pgs", "pgssub",
        "dvd_subtitle", "dvdsub", "vobsub",
        "dvb_subtitle", "dvbsub",
        "xsub",
    ]

    init(burnsSubtitles: Bool, usesStyledRenderer: Bool, codec: String?) {
        if burnsSubtitles {
            self = .burnedIn
        } else if usesStyledRenderer {
            self = .styledASS
        } else if let codec, Self.bitmapCodecs.contains(codec) {
            self = .bitmap
        } else {
            self = .available
        }
    }

    var isAvailable: Bool {
        switch self {
        case .available, .bitmap: true
        case .styledASS, .burnedIn: false
        }
    }

    var allowsTextStyling: Bool {
        self == .available
    }

    var message: String? {
        switch self {
        case .available, .bitmap: nil
        case .styledASS: String(localized: "player.settings.subtitles.appearance.styledASS")
        case .burnedIn: String(localized: "player.settings.sync.subtitles.burnedIn")
        }
    }

    /// A sample line lets the settings be judged between two cues, on tracks that draw them as text.
    var samplePreviewText: String? {
        allowsTextStyling ? String(localized: "settings.playback.subtitles.preview.sample") : nil
    }
}

extension PlayerController {
    func subtitleAppearanceAvailability(burnsSubtitles: Bool) -> SubtitleAppearanceAvailability {
        SubtitleAppearanceAvailability(
            burnsSubtitles: burnsSubtitles,
            usesStyledRenderer: assRenderer != nil,
            codec: activeSubtitleCodec,
        )
    }
}
