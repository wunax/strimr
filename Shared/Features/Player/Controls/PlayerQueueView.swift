import SwiftUI

enum PlayerQueueLayout {
    case carousel
    case drawer
}

@MainActor
struct PlayerQueueView: View {
    let items: [PlaybackQueueItem]
    let currentIndex: Int
    let services: MediaServices
    let layout: PlayerQueueLayout
    let onSelect: (Int) -> Void
    let onClose: () -> Void
    var showsCarouselHeader = true
    var focusesCurrentItemOnAppear = true

    #if os(tvOS)
        @FocusState private var focusedItemID: UUID?
    #endif

    var body: some View {
        switch layout {
        case .carousel:
            carousel
        case .drawer:
            drawer
        }
    }

    private var carousel: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsCarouselHeader {
                HStack(spacing: 10) {
                    Label("player.queue.title", systemImage: "list.bullet.rectangle")
                        .font(.sectionTitle)
                        .foregroundStyle(.textPrimary)

                    Spacer()

                    Text(String(localized: "player.queue.count \(items.count)"))
                        .font(.cardMetadata)
                        .foregroundStyle(.textSecondary)
                }
            }

            ScrollViewReader { proxy in
                ScrollView(.horizontal, showsIndicators: false) {
                    LazyHStack(alignment: .top, spacing: carouselItemSpacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            queueItemButton(item: item, index: index, layout: .carousel)
                        }
                    }
                    .padding(.horizontal, carouselContentHorizontalPadding)
                    .padding(.vertical, carouselContentVerticalPadding)
                }
                .onAppear {
                    scrollToCurrentItem(with: proxy, anchor: .leading)
                }
            }
            #if os(iOS) || os(tvOS)
            .scrollClipDisabled()
            #endif
            #if os(tvOS)
            .focusSection()
            .defaultFocus($focusedItemID, currentItem?.id)
            #endif
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, carouselBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        #if os(tvOS)
            .onAppear {
                guard focusesCurrentItemOnAppear else { return }
                focusedItemID = currentItem?.id
            }
        #endif
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label("player.queue.title", systemImage: "list.bullet.rectangle")
                    .font(.sectionTitle)

                Spacer()

                Button("common.actions.close", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "player.queue.close"))
            }

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            queueItemButton(item: item, index: index, layout: .drawer)
                        }
                    }
                }
                .onAppear {
                    scrollToCurrentItem(with: proxy, anchor: .top)
                }
            }
        }
        .padding(22)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.textPrimary)
        .videoOverlayGlass(in: Rectangle())
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.strokeSubtle)
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func queueItemButton(
        item: PlaybackQueueItem,
        index: Int,
        layout: PlayerQueueLayout,
    ) -> some View {
        #if os(tvOS)
            itemView(item: item, index: index, layout: layout, isFocused: focusedItemID == item.id)
                .focusable()
                .focused($focusedItemID, equals: item.id)
                .onTapGesture {
                    onSelect(index)
                }
                .accessibilityAddTraits(.isButton)
        #else
            let button = Button {
                onSelect(index)
            } label: {
                itemView(item: item, index: index, layout: layout, isFocused: false)
            }
            switch layout {
            case .carousel:
                button.buttonStyle(.cardLift)
            case .drawer:
                button.buttonStyle(.plain)
            }
        #endif
    }

    private func itemView(
        item: PlaybackQueueItem,
        index: Int,
        layout: PlayerQueueLayout,
        isFocused: Bool,
    ) -> some View {
        PlayerQueueItemView(
            item: item,
            position: index + 1,
            totalCount: items.count,
            isCurrent: index == currentIndex,
            isPlayed: index < currentIndex,
            isFocused: isFocused,
            services: services,
            layout: layout,
        )
    }

    private func scrollToCurrentItem(with proxy: ScrollViewProxy, anchor: UnitPoint) {
        guard let currentItem else { return }
        proxy.scrollTo(currentItem.id, anchor: anchor)
    }

    private var currentItem: PlaybackQueueItem? {
        guard items.indices.contains(currentIndex) else { return nil }
        return items[currentIndex]
    }

    private var carouselItemSpacing: CGFloat {
        #if os(tvOS)
            40
        #else
            16
        #endif
    }

    private var carouselContentHorizontalPadding: CGFloat {
        #if os(tvOS)
            36
        #else
            2
        #endif
    }

    private var carouselContentVerticalPadding: CGFloat {
        #if os(tvOS)
            28
        #else
            4
        #endif
    }

    private var carouselBottomPadding: CGFloat {
        #if os(iOS)
            8
        #else
            26
        #endif
    }
}

@MainActor
struct PlayerQueueItemView: View {
    let item: PlaybackQueueItem
    let position: Int
    let totalCount: Int
    let isCurrent: Bool
    let isPlayed: Bool
    let isFocused: Bool
    let services: MediaServices
    let layout: PlayerQueueLayout

    private var media: MediaItem {
        item.media
    }

    private var cardWidth: CGFloat {
        switch layout {
        case .carousel:
            #if os(iOS)
                190
            #elseif os(tvOS)
                280
            #else
                220
            #endif
        case .drawer:
            150
        }
    }

    private var artworkWidth: CGFloat {
        cardWidth
    }

    private var artworkHeight: CGFloat {
        artworkWidth * 9 / 16
    }

    private var accessibilityTitle: String {
        if media.type == .episode {
            return "\(media.primaryLabel), \(media.title)"
        }
        return media.primaryLabel
    }

    var body: some View {
        content
            .opacity(isPlayed && !isFocused ? 0.5 : 1)
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "player.queue.item.accessibility \(position) \(totalCount) \(accessibilityTitle)",
                ),
            )
    }

    @ViewBuilder
    private var content: some View {
        switch layout {
        case .carousel:
            VStack(alignment: .leading, spacing: LayoutMetrics.cardLabelSpacing) {
                artwork
                    .cardFocusStyle(isFocused: isFocused)
                details
            }
            .frame(width: cardWidth, alignment: .leading)
            .contentShape(Rectangle())
        case .drawer:
            HStack(alignment: .top, spacing: 12) {
                artwork
                details
            }
            .padding(9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                isCurrent ? Color.surfaceRaised : .surfaceSubtle,
                in: RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous),
            )
        }
    }

    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            if media.type == .episode {
                Text(media.primaryLabel)
                    .font(.cardMetadata)
                    .foregroundStyle(.textSecondary)
                    .lineLimit(1)

                Text(media.title)
                    .font(.cardTitle)
                    .lineLimit(2)

                if let episodeLabel = media.tertiaryLabel {
                    Text(episodeLabel)
                        .font(.cardMetadata)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
            } else {
                Text(media.primaryLabel)
                    .font(.cardTitle)
                    .lineLimit(2)

                if let secondaryLabel = media.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.cardMetadata)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                }
            }

            if let duration = media.duration {
                Text(duration.mediaDurationText())
                    .font(.cardMetadata.monospacedDigit())
                    .foregroundStyle(.textSecondary)
            }
        }
        .foregroundStyle(.textPrimary)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var artwork: some View {
        MediaImageView(
            viewModel: MediaImageViewModel(
                services: services,
                artworkKind: .art,
                media: .playable(media),
            ),
        )
        .frame(width: artworkWidth, height: artworkHeight)
        .mediaArtworkStyle(layout == .carousel ? .standard : .compact)
        .overlay(alignment: .topLeading) {
            if isCurrent {
                Text("player.queue.current")
                    .font(.badge)
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    .padding(8)
            }
        }
    }
}
