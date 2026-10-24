import SwiftUI

/// A playlist position: its number, a 16:9 image and what is playing there.
struct PlaylistEntryRow: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    let entry: PlaylistEntry
    let position: Int
    /// The highest position in the list, which sets the width of the number column.
    let lastPosition: Int
    /// Nil where the list handles clicks itself, as on macOS where a double click plays.
    var onTap: (() -> Void)?

    private var media: MediaDisplayItem {
        entry.media
    }

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
        HStack(spacing: metrics.spacing) {
            positionLabel
            artwork
            details
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(.vertical, metrics.verticalPadding)
        .modifier(MediaListRowHighlight(isFocused: isHighlighted))
        .contentShape(Rectangle())
        .offlineAvailability(of: media)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused, let playableItem = media.playableItem {
                    focusModel.focus(playableItem)
                }
            }
            .onPlayPauseCommand { onTap?() }
        #endif
            .modifier(TapAction(action: onTap))
            .accessibilityElement(children: .combine)
    }

    /// As wide as the highest number, so titles stay aligned without pushing short lists off the margin.
    private var positionLabel: some View {
        ZStack(alignment: .trailing) {
            Text(lastPosition, format: .number)
                .hidden()
            Text(position, format: .number)
        }
        .font(.facts)
        .monospacedDigit()
        .foregroundStyle(.textTertiary)
    }

    private var artwork: some View {
        ItemArtworkView(
            services: registry.services(for: media, scoped: scopedServices),
            kind: .art,
            media: media,
        )
        .frame(width: metrics.wideSize.width, height: metrics.wideSize.height)
        .mediaArtworkStyle(.compact)
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: media)
        }
        .overlay(alignment: .bottom) {
            if let progress = media.viewProgressPercentage.map({ $0 / 100 }) {
                CardProgressBar(progress: progress)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.title)
                .font(.rowTitle)
                .foregroundStyle(.textPrimary)
                .lineLimit(2)
            if let subtitle = media.listSubtitle {
                Text(subtitle)
                    .font(.facts)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)
            }
            if let metadata = media.listMetadataLine {
                Text(metadata)
                    .font(.cardMetadata)
                    .foregroundStyle(.textTertiary)
                    .lineLimit(1)
            }
        }
    }
}

private struct TapAction: ViewModifier {
    let action: (() -> Void)?

    func body(content: Content) -> some View {
        if let action {
            content
                .onTapGesture(perform: action)
                .accessibilityAddTraits(.isButton)
        } else {
            content
        }
    }
}
