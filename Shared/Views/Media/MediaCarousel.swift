import SwiftUI

struct MediaCarousel: View {
    enum Layout { case portrait, landscape }

    @Environment(\.horizontalSizeClass) private var sizeClass
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
            LazyHStack(alignment: .top, spacing: spacing(for: layout)) {
                ForEach(items, id: \.id) { item in
                    card(for: item)
                }
                if let onViewAll {
                    viewAllCard(action: onViewAll)
                }
            }
            #if os(tvOS)
            .padding(.vertical, 20)
            .padding(.horizontal, 16)
            #else
            .padding(.horizontal, 2)
            #endif
        }
        .mouseDragScrolling()
        #if os(tvOS)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.brandSecondary.opacity(0.24), lineWidth: 1)
        }
        #if os(tvOS)
        .scaleEffect(isViewAllFocused ? 1.12 : 1)
        .animation(.easeOut(duration: 0.15), value: isViewAllFocused)
        #endif
    }

    private func cardSize(for layout: Layout) -> CGSize {
        switch layout {
        case .portrait:
            let height: CGFloat
            #if os(tvOS)
                height = 320
            #elseif os(macOS)
                height = 260
            #else
                height = sizeClass == .compact ? 180 : 240
            #endif
            return CGSize(width: height * 2 / 3, height: height)
        case .landscape:
            let height: CGFloat
            #if os(tvOS)
                height = 180
            #elseif os(macOS)
                height = 140
            #else
                height = sizeClass == .compact ? 90 : 124
            #endif
            return CGSize(width: height * 16 / 9, height: height)
        }
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

    private func spacing(for layout: Layout) -> CGFloat {
        switch layout {
        case .portrait:
            #if os(tvOS)
                28
            #else
                12
            #endif
        case .landscape:
            #if os(tvOS)
                32
            #else
                16
            #endif
        }
    }
}
