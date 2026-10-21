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

    static var surfaceSubtle: Color {
        .white.opacity(0.09)
    }

    static var surfaceRaised: Color {
        .white.opacity(0.14)
    }

    static var strokeSubtle: Color {
        .white.opacity(0.18)
    }

    static var progressTrack: Color {
        .white.opacity(0.25)
    }

    static var progressFill: Color {
        .white
    }
}
