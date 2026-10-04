import SwiftUI

struct FolderListRow: View {
    let title: String
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @FocusState private var isFocused: Bool
    #endif

    private var metrics: MediaListRowMetrics {
        MediaListRowMetrics(sizeClass: sizeClass)
    }

    private var isHighlighted: Bool {
        #if os(tvOS)
            isFocused
        #else
            false
        #endif
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: metrics.spacing) {
                ZStack {
                    RoundedRectangle(cornerRadius: MediaArtworkMetrics.compactCornerRadius, style: .continuous)
                        .fill(Color.gray.opacity(0.15))
                    Image(systemName: "folder.fill")
                        .font(.title2.weight(.semibold))
                        .foregroundStyle(.gray)
                }
                .frame(width: metrics.posterSize.width, height: metrics.posterSize.height)

                Text(title)
                    .font(.headline)
                    .lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Image(systemName: "chevron.right")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.vertical, metrics.verticalPadding)
            .modifier(MediaListRowHighlight(isFocused: isHighlighted))

            #if !os(tvOS)
                Divider()
                    .padding(.leading, metrics.posterSize.width + metrics.spacing)
            #endif
        }
        .contentShape(Rectangle())
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onPlayPauseCommand(perform: onTap)
        #endif
            .onTapGesture(perform: onTap)
    }
}
