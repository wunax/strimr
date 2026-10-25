import SwiftUI

struct MediaCarousel: View {
    enum Layout { case portrait, landscape }

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(\.railPageMargin) private var pageMargin
    #if os(tvOS)
        @FocusState private var isViewAllFocused: Bool
        @FocusState private var focusedItemID: String?
        @State private var lastFocusedItemID: String?
    #elseif os(macOS)
        @State private var isViewAllFocused = false
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
                    #if os(tvOS)
                        .focused($focusedItemID, equals: item.id)
                    #endif
                }
                if let onViewAll {
                    viewAllCard(action: onViewAll)
                }
            }
            .padding(.vertical, LayoutMetrics.railVerticalInset)
        }
        #if !os(tvOS)
        // Gives the lifted card room inside the clipping scroll view without moving the rail.
        .padding(.vertical, -LayoutMetrics.railVerticalInset)
        #endif
        .railBleed(pageMargin: pageMargin)
        .mouseDragScrolling()
        #if os(tvOS)
            .scrollClipDisabled()
            .focusSection()
            .onChange(of: focusedItemID) { oldID, newID in
                guard let newID else { return }
                // `defaultFocus` is ignored when entering a focus section with the remote, so redirect by hand.
                if oldID == nil, let target = entryItemID, target != newID {
                    focusedItemID = target
                    return
                }
                lastFocusedItemID = newID
            }
            .onChange(of: isViewAllFocused) { _, isFocused in
                // Moving back from "View all" lands on the last card, which must not be redirected.
                if isFocused {
                    lastFocusedItemID = items.last?.id
                }
            }
        #endif
    }

    #if os(tvOS)
        private var entryItemID: String? {
            if let lastFocusedItemID, items.contains(where: { $0.id == lastFocusedItemID }) {
                return lastFocusedItemID
            }
            return items.first?.id
        }
    #endif

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
            #if os(macOS)
                .onHover { isViewAllFocused = $0 }
            #endif
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
        .foregroundStyle(.textSecondary)
        .frame(width: size.width, height: size.height)
        .background(.surfaceSubtle)
        .mediaArtworkStyle(borderColor: .strokeSubtle)
        #if os(tvOS) || os(macOS)
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
