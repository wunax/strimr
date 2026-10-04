import SwiftUI

struct MediaCard: View {
    @Environment(ServerRegistry.self) private var registry
    @Environment(MediaServices.self) private var scopedServices: MediaServices?
    #if os(tvOS)
        @Environment(MediaFocusModel.self) private var focusModel
        @FocusState private var isFocused: Bool
    #endif

    let size: CGSize
    let media: MediaDisplayItem
    let artworkKind: MediaImageViewModel.ArtworkKind
    let showsLabels: Bool
    let onTap: () -> Void

    private var progress: Double? {
        media.viewProgressPercentage.map { $0 / 100 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: labelSpacing) {
            artwork
            #if os(tvOS)
                .scaleEffect(isFocused ? 1.12 : 1)
                .animation(.easeOut(duration: 0.15), value: isFocused)
            #endif

            if showsLabels {
                VStack(alignment: .leading, spacing: 4) {
                    Text(media.primaryLabel)
                        .font(primaryLabelFont)
                        .lineLimit(1)
                    Text(media.secondaryLabel ?? "")
                        .font(secondaryLabelFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    Text(media.tertiaryLabel ?? "")
                        .font(secondaryLabelFont)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
        }
        .frame(width: size.width, alignment: .leading)
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
            kind: artworkKind,
            media: media,
        )
        .frame(width: size.width, height: size.height)
        .mediaArtworkStyle()
        .overlay(alignment: .topTrailing) {
            WatchStatusBadge(media: media)
        }
        .downloadStatusOverlay(media)
        .overlay(alignment: .bottomLeading) {
            if let progress {
                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(.brandPrimary)
                    .padding(.horizontal, 10)
                    .padding(.bottom, 10)
            }
        }
    }

    private var labelSpacing: CGFloat {
        #if os(tvOS)
            20
        #else
            8
        #endif
    }

    private var primaryLabelFont: Font {
        #if os(tvOS)
            size.width < 180 ? .footnote : .subheadline
        #else
            .subheadline
        #endif
    }

    private var secondaryLabelFont: Font {
        #if os(tvOS)
            size.width < 180 ? .caption2 : .footnote
        #else
            .footnote
        #endif
    }
}

extension View {
    /// Download badge on artwork; tvOS has no downloads.
    @ViewBuilder
    func downloadStatusOverlay(_ media: MediaDisplayItem) -> some View {
        #if os(tvOS)
            self
        #else
            overlay(alignment: .bottomTrailing) {
                DownloadStatusBadge(media: media)
            }
        #endif
    }

    /// Greys out items that cannot be played while their server is unreachable; tvOS has no offline mode.
    @ViewBuilder
    func offlineAvailability(of media: MediaDisplayItem) -> some View {
        #if os(tvOS)
            self
        #else
            modifier(OfflineDimmingModifier(media: media, server: media.server))
        #endif
    }
}

/// Artwork of an item loaded through its server's services; a plain placeholder when the server is not available.
struct ItemArtworkView: View {
    let services: MediaServices?
    let kind: MediaImageViewModel.ArtworkKind
    let media: MediaDisplayItem

    var body: some View {
        if let services {
            MediaImageView(viewModel: MediaImageViewModel(services: services, artworkKind: kind, media: media))
        } else {
            Rectangle()
                .fill(.gray.opacity(0.15))
        }
    }
}
