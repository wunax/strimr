import SwiftUI

struct MediaCarousel: View {
    enum Layout { case portrait, landscape }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.railPageMargin) private var pageMargin
    #if os(tvOS)
        @FocusState private var isViewAllFocused: Bool
    #endif

    let layout: Layout
    let items: [MediaDisplayItem]
    let showsLabels: Bool
    let onViewAll: (() -> Void)?
    let onSelectMedia: (MediaDisplayItem) -> Void

    init(
        layout: Layout,
        items: [MediaDisplayItem],
        showsLabels: Bool,
        onViewAll: (() -> Void)? = nil,
        onSelectMedia: @escaping (MediaDisplayItem) -> Void,
    ) {
        self.layout = layout
        self.items = items
        self.showsLabels = showsLabels
        self.onViewAll = onViewAll
        self.onSelectMedia = onSelectMedia
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: layout)) {
                ForEach(items, id: \.id) { item in
                    card(for: item)
                }
                if let onViewAll {
                    viewAllCard(action: onViewAll)
                }
            }
            #if os(tvOS)
            .padding(.vertical, LayoutMetrics.tvRailVerticalInset)
            #endif
        }
        .railBleed(pageMargin: pageMargin)
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
            .focusSection()
        #endif
    }

    @ViewBuilder
    private func card(for media: MediaDisplayItem) -> some View {
        switch layout {
        case .portrait:
            PortraitMediaCard(media: media, showsLabels: showsLabels) {
                onSelectMedia(media)
            }
        case .landscape:
            LandscapeMediaCard(media: media, showsLabels: showsLabels) {
                onSelectMedia(media)
            }
        }
    }

    private func viewAllCard(action: @escaping () -> Void) -> some View {
        let size = cardSize(for: layout)
        let card = viewAllCardContent(size: size)

        #if os(tvOS)
            return card
                .focusable()
                .focused($isViewAllFocused)
                .onPlayPauseCommand(perform: action)
                .onTapGesture(perform: action)
                .frame(width: size.width, alignment: .leading)
        #else
            return Button(action: action) {
                card
            }
            .buttonStyle(.plain)
            .frame(width: size.width, alignment: .leading)
        #endif
    }

    private func viewAllCardContent(size: CGSize) -> some View {
        VStack(spacing: 12) {
            Image(systemName: "rectangle.stack.badge.plus")
                .font(.system(size: iconSize(for: layout), weight: .semibold))
            Text("hub.viewAll")
                .font(labelFont)
                .fontWeight(.semibold)
                .multilineTextAlignment(.center)
        }
        .foregroundStyle(.brandSecondary)
        .frame(width: size.width, height: size.height)
        .background(Color.brandSecondary.opacity(0.08))
        .mediaArtworkStyle(borderColor: Color.brandSecondary.opacity(0.24))
        #if os(tvOS)
            .cardFocusStyle(isFocused: isViewAllFocused)
        #endif
    }

    private func cardSize(for layout: Layout) -> CGSize {
        LayoutMetrics.cardSize(
            for: layout,
            sizeClass: sizeClass,
            posterScale: settingsManager.interface.posterSize.scale,
        )
    }

    private func iconSize(for layout: Layout) -> CGFloat {
        switch layout {
        case .portrait:
            #if os(tvOS)
                56
            #else
                34
            #endif
        case .landscape:
            #if os(tvOS)
                44
            #else
                28
            #endif
        }
    }

    private var labelFont: Font {
        #if os(tvOS)
            .headline
        #else
            .subheadline
        #endif
    }
}
