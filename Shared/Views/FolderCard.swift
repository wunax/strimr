import SwiftUI

struct FolderCard: View {
    let title: String
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\ .horizontalSizeClass) private var sizeClass

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

        VStack(alignment: .leading, spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.gray.opacity(0.15))

                VStack(spacing: 8) {
                    Image(systemName: "folder.fill")
                        .font(.system(size: 32, weight: .semibold))
                        .foregroundStyle(Color.brandPrimary)
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            .frame(width: resolvedWidth, height: resolvedHeight)

            if showsLabels {
                Text(title)
                    .font(.subheadline)
                    .lineLimit(1)
            }
        }
        .frame(width: resolvedWidth, alignment: .leading)
        .onTapGesture(perform: onTap)
    }
}
