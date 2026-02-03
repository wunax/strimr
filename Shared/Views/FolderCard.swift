import SwiftUI

struct FolderCard: View {
    let title: String
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @FocusState private var isFocused: Bool
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
        if sizeClass == .compact {
            180
        } else {
            240
        }
    }

    var body: some View {
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        let resolvedWidth = width ?? (height.map { $0 * aspectRatio } ?? resolvedHeight * aspectRatio)

        VStack(alignment: .leading, spacing: labelSpacing) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.15))

                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(.gray)
                }
            }
            .frame(width: resolvedWidth, height: resolvedHeight)
            #if os(tvOS)
                .scaleEffect(isFocused ? 1.12 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
            #endif

            if showsLabels {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .frame(width: resolvedWidth, alignment: .leading)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onPlayPauseCommand(perform: onTap)
        #endif
            .onTapGesture(perform: onTap)
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            8
        #endif
    }
}
