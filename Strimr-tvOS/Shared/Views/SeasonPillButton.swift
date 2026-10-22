import SwiftUI

/// Season chip of a detail page; white once selected, like the play button.
struct SeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    var body: some View {
        Text(title)
            .font(.facts.weight(.semibold))
            .padding(.horizontal, 22)
            .padding(.vertical, 10)
            .foregroundStyle(isSelected ? Color.black : Color.textPrimary)
            .background(Capsule(style: .continuous).fill(background))
            .scaleEffect(isFocused && !reduceMotion ? CardFocusStyle.focusedScale : 1)
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
            .animation(Motion.crossfade, value: isSelected)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    onFocus()
                } else {
                    onBlur()
                }
            }
            .onPlayPauseCommand(perform: onSelect)
            .onTapGesture(perform: onSelect)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var background: Color {
        if isSelected {
            return .white
        }
        return isFocused ? .white.opacity(0.3) : .surfaceRaised
    }
}
