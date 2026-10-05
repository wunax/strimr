import SwiftUI

struct MediaListRowMetrics {
    let posterSize: CGSize
    let wideSize: CGSize
    let summaryLineLimit: Int
    let spacing: CGFloat

    init(sizeClass: UserInterfaceSizeClass?) {
        #if os(tvOS)
            posterSize = CGSize(width: 120, height: 180)
            wideSize = CGSize(width: 240, height: 135)
            summaryLineLimit = 3
            spacing = 32
        #elseif os(macOS)
            posterSize = CGSize(width: 80, height: 120)
            wideSize = CGSize(width: 160, height: 90)
            summaryLineLimit = 3
            spacing = 16
        #else
            if sizeClass == .compact {
                posterSize = CGSize(width: 60, height: 90)
                wideSize = CGSize(width: 120, height: 68)
                summaryLineLimit = 2
                spacing = 12
            } else {
                posterSize = CGSize(width: 80, height: 120)
                wideSize = CGSize(width: 160, height: 90)
                summaryLineLimit = 3
                spacing = 16
            }
        #endif
    }

    var verticalPadding: CGFloat {
        #if os(tvOS)
            16
        #else
            10
        #endif
    }

    /// Fixed on tvOS so placeholders keep `scrollTo(index)` and the character column aligned.
    var rowHeight: CGFloat {
        posterSize.height + verticalPadding * 2
    }
}

/// Full-width focus effect for list rows on tvOS.
struct MediaListRowHighlight: ViewModifier {
    let isFocused: Bool

    func body(content: Content) -> some View {
        #if os(tvOS)
            content
                .padding(.horizontal, 16)
                .background(
                    RoundedRectangle(cornerRadius: 20, style: .continuous)
                        .fill(isFocused ? Color.white.opacity(0.15) : Color.clear),
                )
                .scaleEffect(isFocused ? 1.02 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
        #else
            content
        #endif
    }
}

struct MediaListRow: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.horizontalSizeClass) private var sizeClass
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    let media: MediaDisplayItem
    let onTap: () -> Void

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

    private var artworkSize: CGSize {
        media.usesWideListArtwork ? metrics.wideSize : metrics.posterSize
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: metrics.spacing) {
                artwork
                details
                    .frame(maxWidth: .infinity, alignment: .leading)
                WatchStatusBadge(media: media)
            }
            .padding(.vertical, metrics.verticalPadding)
            .modifier(MediaListRowHighlight(isFocused: isHighlighted))

            #if !os(tvOS)
                Divider()
                    .padding(.leading, artworkSize.width + metrics.spacing)
            #endif
        }
        .contentShape(Rectangle())
        .offlineAvailability(of: media)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused, let playableItem = media.playableItem {
                    focusModel.focusedMedia = playableItem
                }
            }
            .onPlayPauseCommand(perform: onTap)
        #endif
            .onTapGesture(perform: onTap)
    }

    private var artwork: some View {
        ItemArtworkView(
            services: registry.services(for: media, scoped: scopedServices),
            kind: media.usesWideListArtwork ? .art : .thumb,
            media: media,
        )
        .frame(width: artworkSize.width, height: artworkSize.height)
        .mediaArtworkStyle(.compact)
        .overlay(alignment: .bottom) {
            if let progress = media.viewProgressPercentage.map({ $0 / 100 }) {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.brandPrimary)
                    .padding(.horizontal, 6)
                    .padding(.bottom, 6)
            }
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.title)
                .font(.headline)
                .lineLimit(2)
            if let subtitle = media.listSubtitle {
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let metadata = media.listMetadataLine {
                Text(metadata)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            summary
                .padding(.top, 2)
        }
    }

    @ViewBuilder
    private var summary: some View {
        if media.playableItem?.shouldHideSpoilerSummary(at: settingsManager.interface.spoilerProtection) == true {
            Label("media.spoilerProtection.summaryHidden", systemImage: "eye.slash")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(1)
        } else if let summary = media.summary, !summary.isEmpty {
            Text(summary)
                .font(.footnote)
                .foregroundStyle(.secondary)
                .lineLimit(metrics.summaryLineLimit)
        }
    }
}
