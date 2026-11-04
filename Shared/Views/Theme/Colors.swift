import SwiftUI

extension ShapeStyle where Self == Color {
    static var textPrimary: Color {
        .white
    }

    static var textSecondary: Color {
        .white.opacity(0.65)
    }

    static var textTertiary: Color {
        .white.opacity(0.45)
    }

    /// The one color of selected states: a checkmark, the current option, the active category.
    static var selectionAccent: Color {
        .brandPrimary
    }

    static var surfaceSubtle: Color {
        .white.opacity(0.09)
    }

    static var surfaceRaised: Color {
        .white.opacity(0.14)
    }

    static var strokeSubtle: Color {
        .white.opacity(0.18)
    }

    /// Dims the page or video behind a modal, prompt or panel.
    static var overlayScrim: Color {
        .black.opacity(0.6)
    }

    /// Dark pill behind status badges laid over artwork, so they stay legible on any image.
    static var badgeBackground: Color {
        .black.opacity(0.65)
    }

    static var progressTrack: Color {
        .white.opacity(0.25)
    }

    /// Part of a playback timeline already loaded ahead of the playhead.
    static var progressBuffered: Color {
        .white.opacity(0.55)
    }

    static var progressFill: Color {
        .white
    }

    /// Marks what is on air right now: the guide's current time line and the live badge.
    static var liveIndicator: Color {
        Color(red: 1, green: 0.27, blue: 0.23)
    }

    /// Marks a program that records or will record.
    static var recordingIndicator: Color {
        Color(red: 1, green: 0.27, blue: 0.23)
    }

    /// Intro, credits and commercial spans on a playback timeline, translucent so the played fill still shows through.
    static var progressSegment: Color {
        Color(red: 1, green: 0.76, blue: 0.28).opacity(0.7)
    }
}

extension LiveTVCategory {
    /// Faint wash behind guide cells, so a category reads at a glance without competing with the titles.
    var guideTint: Color {
        switch self {
        case .sports: Color(red: 0.2, green: 0.75, blue: 0.4)
        case .movie: Color(red: 0.6, green: 0.4, blue: 0.95)
        case .series: Color(red: 0.3, green: 0.55, blue: 1)
        case .news: Color(red: 1, green: 0.6, blue: 0.2)
        case .kids: Color(red: 1, green: 0.85, blue: 0.3)
        }
    }
}
