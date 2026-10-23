import SwiftUI

/// Season chip of a tvOS detail page. Not a button, so its focus can drive the rails around it.
struct SeasonPillButton: View {
    let title: String
    let isSelected: Bool
    let onSelect: () -> Void
    var onFocus: () -> Void = {}
    var onBlur: () -> Void = {}

    @FocusState private var isFocused: Bool

    var body: some View {
        Text(title)
            .chipAppearance(isSelected: isSelected, isFocused: isFocused)
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
}
