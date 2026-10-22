import SwiftUI

struct SeerrMediaCard: View {
    let media: SeerrMedia
    let height: CGFloat?
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SettingsManager.self) private var settingsManager
    #if os(tvOS)
        @Environment(SeerrFocusModel.self) private var focusModel
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool
    #elseif os(macOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isFocused = false
    #endif

    private let aspectRatio: CGFloat = 2 / 3

    init(
        media: SeerrMedia,
        height: CGFloat? = nil,
        width: CGFloat? = nil,
        showsLabels: Bool = true,
        onTap: @escaping () -> Void,
    ) {
        self.media = media
        self.height = height
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var size: CGSize {
        let defaultHeight = LayoutMetrics.baseCardHeight(for: .portrait, sizeClass: sizeClass)
            * settingsManager.interface.posterSize.scale
        let resolvedHeight = height ?? (width.map { $0 / aspectRatio } ?? defaultHeight)
        return CGSize(width: width ?? resolvedHeight * aspectRatio, height: resolvedHeight)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            SeerrMediaArtworkView(media: media, width: size.width, height: size.height)
            #if os(tvOS) || os(macOS)
                .cardFocusStyle(isFocused: isFocused)
            #endif

            if showsLabels {
                labels
            }
        }
        .frame(width: size.width, alignment: .leading)
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    focusModel.focusedMedia = media
                }
            }
            .onPlayPauseCommand(perform: onTap)
        #elseif os(macOS)
            .contentShape(Rectangle())
            .onHover { isFocused = $0 }
        #endif
            .onTapGesture(perform: onTap)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(media.displayTitle)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(titleOpacity))
                .lineLimit(1)
            Text(media.year.map(String.init) ?? "")
                .font(.cardMetadata)
                .foregroundStyle(.textSecondary)
                .opacity(metadataOpacity)
                .lineLimit(1)
        }
        #if os(tvOS) || os(macOS)
        // Follows the bottom edge of the focused artwork so the lifted card does not cover its caption.
        .offset(y: isFocused && !reduceMotion ? size.height * (CardFocusStyle.focusedScale - 1) / 2 : 0)
        .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
        #endif
    }

    private var titleOpacity: Double {
        #if os(tvOS)
            isFocused ? 1 : 0.45
        #else
            1
        #endif
    }

    /// Matches the unfocused captions of library cards.
    private var metadataOpacity: Double {
        #if os(tvOS)
            isFocused ? 1 : 0.32 / 0.65
        #else
            1
        #endif
    }
}
