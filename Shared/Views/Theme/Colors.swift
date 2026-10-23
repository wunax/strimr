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
}
