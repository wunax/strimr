import SwiftUI

struct ExploreItemArtworkView: View {
    let item: ExploreItem
    let width: CGFloat
    let height: CGFloat

    var body: some View {
        AsyncImage(url: item.posterURL) { phase in
            switch phase {
            case let .success(image):
                image
                    .resizable()
                    .scaledToFill()
            case .empty:
                if item.posterURL == nil {
                    MediaArtworkPlaceholder(mediaKind: item.kind.mediaKind)
                } else {
                    Color.surfaceSubtle
                }
            default:
                MediaArtworkPlaceholder(mediaKind: item.kind.mediaKind)
            }
        }
        .frame(width: width, height: height)
        .mediaArtworkStyle()
        .overlay(alignment: .topTrailing) {
            if let status = item.seerrStatus {
                SeerrAvailabilityBadgeView(
                    status: status,
                    isDownloading: item.seerrMedia?.mediaInfo?.isDownloading ?? false,
                )
                .padding(8)
            }
        }
    }
}

struct ExploreItemCard: View {
    let item: ExploreItem
    let width: CGFloat?
    let showsLabels: Bool
    let onTap: () -> Void

    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(SettingsManager.self) private var settingsManager
    #if os(tvOS)
        @Environment(ExploreFocusModel.self) private var focusModel: ExploreFocusModel?
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @FocusState private var isFocused: Bool
    #elseif os(macOS)
        @Environment(\.accessibilityReduceMotion) private var reduceMotion
        @State private var isFocused = false
    #endif

    private let aspectRatio: CGFloat = 2 / 3

    init(item: ExploreItem, width: CGFloat? = nil, showsLabels: Bool = true, onTap: @escaping () -> Void) {
        self.item = item
        self.width = width
        self.showsLabels = showsLabels
        self.onTap = onTap
    }

    private var size: CGSize {
        let defaultHeight = LayoutMetrics.baseCardHeight(for: .portrait, sizeClass: sizeClass)
            * settingsManager.interface.posterSize.scale
        let height = width.map { $0 / aspectRatio } ?? defaultHeight
        return CGSize(width: width ?? height * aspectRatio, height: height)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
            ExploreItemArtworkView(item: item, width: size.width, height: size.height)
            #if os(tvOS) || os(macOS)
                .cardFocusStyle(isFocused: isFocused)
            #endif

            if showsLabels {
                labels
            }
        }
        .frame(width: size.width, alignment: .leading)
        .contentShape(Rectangle())
        #if os(tvOS)
            .focusable()
            .focused($isFocused)
            .onChange(of: isFocused) { _, focused in
                if focused {
                    focusModel?.focusedItem = item
                }
            }
            .onPlayPauseCommand(perform: onTap)
        #elseif os(macOS)
            .onHover { isFocused = $0 }
        #endif
            .onTapGesture(perform: onTap)
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
    }

    private var labels: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.cardTitle)
                .foregroundStyle(.textPrimary.opacity(titleOpacity))
                .lineLimit(1)
            Text(item.year.map(String.init) ?? "")
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

    private var metadataOpacity: Double {
        #if os(tvOS)
            isFocused ? 1 : 0.32 / 0.65
        #else
            1
        #endif
    }
}

struct ExploreCarousel: View {
    @Environment(\.railPageMargin) private var pageMargin

    let items: [ExploreItem]
    let showsLabels: Bool
    /// On tvOS, where the rail title cannot take focus, See All is a card at the end of the rail.
    var onViewAll: (() -> Void)?
    let onSelect: (ExploreItem) -> Void

    init(
        items: [ExploreItem],
        showsLabels: Bool,
        onViewAll: (() -> Void)? = nil,
        onSelect: @escaping (ExploreItem) -> Void,
    ) {
        self.items = items
        self.showsLabels = showsLabels
        self.onViewAll = onViewAll
        self.onSelect = onSelect
    }

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            LazyHStack(alignment: .top, spacing: LayoutMetrics.railSpacing(for: .portrait)) {
                ForEach(items) { item in
                    ExploreItemCard(item: item, showsLabels: showsLabels) {
                        onSelect(item)
                    }
                }
                #if os(tvOS)
                    if let onViewAll {
                        Button(action: onViewAll) {
                            Label("hub.viewAll", systemImage: "chevron.right")
                                .font(.facts.weight(.semibold))
                                .padding(.horizontal, 12)
                        }
                        .actionButtonStyle(.secondary)
                        .padding(.top, 120)
                    }
                #endif
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
        #endif
    }
}

/// A search result, laid out like a library search result.
struct ExploreSearchRow: View {
    let item: ExploreItem
    let onTap: () -> Void

    /// Hierarchical styles rather than the fixed text tokens: the focused tvOS button turns white and they invert.
    var body: some View {
        Button(action: onTap) {
            HStack(alignment: .top, spacing: 12) {
                ExploreItemArtworkView(item: item, width: 100, height: 150)

                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 8) {
                        Text(item.title)
                            .font(.rowTitle)
                            .lineLimit(2)

                        Spacer(minLength: 8)

                        MediaTypeBadge(type: item.kind.mediaKind)
                    }

                    if let year = item.year {
                        Text(String(year))
                            .font(.facts)
                            .foregroundStyle(.secondary)
                    }

                    if let overview = item.overview, !overview.isEmpty {
                        Text(overview)
                            .font(.facts)
                            .foregroundStyle(.secondary)
                            .lineLimit(3)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(.surfaceSubtle),
            )
        }
        .buttonStyle(.plain)
    }
}
