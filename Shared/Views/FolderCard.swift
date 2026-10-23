import SwiftUI

struct FolderCard: View {
    let title: String
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool
    #elseif os(macOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isFocused = false
    #endif

    private let aspectRatio: CGFloat = 2 / 3

    init(
        title: String,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool,
        onTap: @escaping () -> Void,
    ) {
        self.title = title
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var defaultHeight: CGFloat {
        #if os(macOS)
            260
        #else
            if sizeClass == .compact {
                180
            } else {
                240
            }
        #endif
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)

        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(.surfaceSubtle)

                Image(systemName: "folder.fill")
                    .font(.system(size: 32, weight: .semibold))
                    .foregroundStyle(.textTertiary)
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            #if os(tvOS) || os(macOS)
                .cardFocusStyle(isFocused: isFocused)
            #endif

            if showsLabels {
                Text(title)
                    .font(.cardTitle)
                    .foregroundStyle(.textPrimary)
                    .lineLimit(1)
                #if os(tvOS) || os(macOS)
                    // Follows the bottom edge of the focused artwork, as on media cards.
                    .offset(
                        y: isFocused && !reduceMotion
                            ? resolvedHeight * (CardFocusStyle.focusedScale - 1) / 2
                            : 0,
                    )
                    .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
                #endif
            }
        }
        .frame(width: resolvedWidth, alignment: .leading)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onPlayPauseCommand(perform: onTap)
        #elseif os(macOS)
            .contentShape(Rectangle())
            .onHover { isFocused = $0 }
        #endif
            .onTapGesture(perform: onTap)
    }
}
