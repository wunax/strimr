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
            HStack(spacing: 10) {
                Label("player.queue.title", systemImage: "list.bullet.rectangle")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)

                Spacer()

                Text(String(localized: "player.queue.count \(items.count)"))
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.white.opacity(0.7))
            }

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(alignment: .top, spacing: carouselItemSpacing) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        queueItemButton(item: item, index: index, layout: .carousel)
                    }
                }
                .padding(.horizontal, carouselContentHorizontalPadding)
                .padding(.vertical, carouselContentVerticalPadding)
            }
            #if os(iOS) || os(tvOS)
                .scrollClipDisabled()
            #endif
            #if os(tvOS)
                .focusSection()
            #endif
        }
        .padding(.horizontal, 28)
        .padding(.top, 22)
        .padding(.bottom, carouselBottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .shadow(color: .black.opacity(0.45), radius: 18, x: 0, y: 8)
        #if os(tvOS)
            .onAppear {
                focusedItemID = currentItem?.id
            }
        #endif
    }

    private var drawer: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 10) {
                Label("player.queue.title", systemImage: "list.bullet.rectangle")
                    .font(.title3.weight(.semibold))

                Spacer()

                Button("common.actions.close", systemImage: "xmark", action: onClose)
                    .labelStyle(.iconOnly)
                    .buttonStyle(.bordered)
                    .accessibilityLabel(String(localized: "player.queue.close"))
            }

            ScrollView {
                LazyVStack(spacing: 12) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        queueItemButton(item: item, index: index, layout: .drawer)
                    }
                }
            }
        }
        .padding(22)
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480, maxHeight: .infinity, alignment: .top)
        .foregroundStyle(.white)
        .background(.ultraThinMaterial)
        .overlay(alignment: .leading) {
            Rectangle()
                .fill(.white.opacity(0.12))
                .frame(width: 1)
        }
    }

    @ViewBuilder
    private func queueItemButton(
        item: PlaybackQueueItem,
        index: Int,
        layout: PlayerQueueLayout,
    ) -> some View {
        Button {
            onSelect(index)
        } label: {
            PlayerQueueItemView(
                item: item,
                position: index + 1,
                totalCount: items.count,
                isCurrent: index == currentIndex,
                services: services,
                layout: layout,
            )
        }
        .buttonStyle(.plain)
        #if os(tvOS)
            .focused($focusedItemID, equals: item.id)
        #endif
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
        layout == .carousel ? cardWidth - 18 : cardWidth
    }

    private var artworkHeight: CGFloat {
        artworkWidth * 9 / 16
    }

    private var cardBackgroundOpacity: Double {
        switch layout {
        case .carousel:
            isCurrent ? 0.26 : 0.16
        case .drawer:
            isCurrent ? 0.18 : 0.08
        }
    }

    private var accessibilityTitle: String {
        if media.type == .episode {
            return "\(media.primaryLabel), \(media.title)"
        }
        return media.primaryLabel
    }

    var body: some View {
        content
            .accessibilityElement(children: .combine)
            .accessibilityLabel(
                String(
                    localized: "player.queue.item.accessibility \(position) \(totalCount) \(accessibilityTitle)",
                ),
            )
    }

    @ViewBuilder
    private var content: some View {
        Group {
            switch layout {
            case .carousel:
                VStack(alignment: .leading, spacing: 9) {
                    artwork
                    details
                }
            case .drawer:
                HStack(alignment: .top, spacing: 12) {
                    artwork
                    details
                }
            }
        }
        .padding(9)
        .frame(width: layout == .carousel ? cardWidth : nil, alignment: .leading)
        .frame(maxWidth: layout == .drawer ? .infinity : nil, alignment: .leading)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(cardBackgroundOpacity))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color.white.opacity(0.12), lineWidth: 1)
        }
        #if os(tvOS)
            .scaleEffect(isCurrent ? 1.02 : 1)
        #endif
    }

    @ViewBuilder
    private var details: some View {
        VStack(alignment: .leading, spacing: 3) {
            if media.type == .episode {
                Text(media.primaryLabel)
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)

                Text(media.title)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let episodeLabel = media.tertiaryLabel {
                    Text(episodeLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            } else {
                Text(media.primaryLabel)
                    .font(.subheadline.weight(.semibold))
                    .lineLimit(2)

                if let secondaryLabel = media.secondaryLabel {
                    Text(secondaryLabel)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            if let duration = media.duration {
                Text(duration.mediaDurationText())
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
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
        .mediaArtworkStyle(.compact, borderColor: .white.opacity(0.12))
        .overlay(alignment: .topLeading) {
            if isCurrent {
                Text("player.queue.current")
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 4)
                    .background(.white, in: Capsule())
                    .padding(8)
            }
        }
    }
}

struct PlayerQueueDisclosureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.white.opacity(0.85))
                .frame(width: 32, height: 22)
                .background(.white.opacity(0.12), in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "player.queue.open"))
    }
}

struct PlayerQueueDisclosureIndicator: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 32, height: 22)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}
