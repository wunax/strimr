import SwiftUI

/// Lift applied to card artwork when it takes focus on tvOS, or the pointer on macOS.
struct CardFocusStyle: ViewModifier {
    static var focusedScale: CGFloat {
        #if os(tvOS)
            1.06
        #else
            1.04
        #endif
    }

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    let isFocused: Bool
    let isPressed: Bool

    func body(content: Content) -> some View {
        content
            .shadow(
                color: .black.opacity(isFocused ? 0.45 : 0.3),
                radius: isFocused ? 18 : 8,
                y: isFocused ? 8 : 0,
            )
            .animation(Motion.focus, value: isFocused)
            .scaleEffect(scale)
            .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: scale)
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if isPressed {
            return 0.97
        }
        return isFocused ? Self.focusedScale : 1
    }
}

extension View {
    func cardFocusStyle(isFocused: Bool, isPressed: Bool = false) -> some View {
        modifier(CardFocusStyle(isFocused: isFocused, isPressed: isPressed))
    }
}

/// Card lift for a whole button: on focus on tvOS, under the pointer on macOS, and while pressed everywhere.
struct CardLiftButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Lifted(configuration: configuration)
    }

    private struct Lifted: View {
        let configuration: Configuration
        #if os(tvOS)
            @Environment(\.isFocused) private var isFocused
        #elseif os(macOS)
            @State private var isFocused = false
        #else
            private let isFocused = false
        #endif

        var body: some View {
            configuration.label
                .cardFocusStyle(isFocused: isFocused, isPressed: configuration.isPressed)
            #if os(macOS)
                .onHover { isFocused = $0 }
            #endif
        }
    }
}

extension ButtonStyle where Self == CardLiftButtonStyle {
    static var cardLift: CardLiftButtonStyle {
        CardLiftButtonStyle()
    }
}

#if os(macOS)
    /// Pointer counterpart of the tvOS focus lift for buttons that are not cards: a slight grow and a soft shadow.
    struct HoverLift: ViewModifier {
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @Environment(\.isEnabled) private var isEnabled
        @State private var isHovered = false

        let scale: CGFloat

        func body(content: Content) -> some View {
            content
                .shadow(color: .black.opacity(isLifted ? 0.35 : 0), radius: 12, y: 4)
                .animation(Motion.focus, value: isLifted)
                .scaleEffect(isLifted && !reduceMotion ? scale : 1)
                .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isLifted)
                .onHover { isHovered = $0 }
        }

        private var isLifted: Bool {
            isHovered && isEnabled
        }
    }

    extension View {
        func hoverLift(scale: CGFloat = 1.06) -> some View {
            modifier(HoverLift(scale: scale))
        }
    }
#endif
