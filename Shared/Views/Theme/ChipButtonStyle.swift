import SwiftUI

extension View {
    /// Capsule of a selectable option, such as a filter or a season: white once selected, like the play button.
    func chipAppearance(isSelected: Bool, isFocused: Bool = false) -> some View {
        modifier(ChipAppearance(isSelected: isSelected, isFocused: isFocused))
    }
}

private struct ChipAppearance: ViewModifier {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isSelected: Bool
    let isFocused: Bool

    func body(content: Content) -> some View {
        content
            .font(.facts.weight(.semibold))
            .lineLimit(1)
            .padding(.horizontal, horizontalPadding)
            .padding(.vertical, verticalPadding)
            .foregroundStyle(isSelected ? Color.black : .textPrimary)
            .background(background, in: Capsule(style: .continuous))
            .contentShape(Capsule(style: .continuous))
            .scaleEffect(isFocused && !reduceMotion ? CardFocusStyle.focusedScale : 1)
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
            .animation(Motion.crossfade, value: isSelected)
    }

    private var background: Color {
        if isSelected {
            return .white
        }
        return isFocused ? .white.opacity(0.3) : .surfaceRaised
    }

    private var horizontalPadding: CGFloat {
        #if os(tvOS)
            22
        #else
            14
        #endif
    }

    private var verticalPadding: CGFloat {
        #if os(tvOS)
            10
        #else
            8
        #endif
    }
}

/// Button counterpart of `chipAppearance`, which draws the tvOS focus itself instead of the system highlight.
struct ChipButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        Chip(isSelected: isSelected, configuration: configuration)
    }

    private struct Chip: View {
        #if os(tvOS)
            @Environment(\.isFocused) private var isFocused
        #else
            private let isFocused = false
        #endif

        let isSelected: Bool
        let configuration: Configuration

        var body: some View {
            configuration.label
                .chipAppearance(isSelected: isSelected, isFocused: isFocused)
                .opacity(configuration.isPressed ? 0.7 : 1)
            #if os(macOS)
                .hoverLift(scale: 1.04)
            #endif
        }
    }
}

extension ButtonStyle where Self == ChipButtonStyle {
    static func chip(isSelected: Bool) -> ChipButtonStyle {
        ChipButtonStyle(isSelected: isSelected)
    }
}
