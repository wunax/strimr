import SwiftUI

/// Lift applied to card artwork when it takes focus.
struct CardFocusStyle: ViewModifier {
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
            .animation(Motion.focusScale, value: scale)
    }

    private var scale: CGFloat {
        guard !reduceMotion else { return 1 }
        if isPressed {
            return 0.97
        }
        return isFocused ? 1.06 : 1
    }
}

extension View {
    func cardFocusStyle(isFocused: Bool, isPressed: Bool = false) -> some View {
        modifier(CardFocusStyle(isFocused: isFocused, isPressed: isPressed))
    }
}
