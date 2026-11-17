import SwiftUI

/// Tabs below the system style timeline: Info, Chapters and the queue, with the same content as the classic info
/// panel. Focusing a tab opens it, as in the system player.
struct SystemPlayerTabsRow: View {
    var tabs: [PlayerInfoTab]
    var selectedTab: PlayerInfoTab
    var isExpanded: Bool
    var focus: FocusState<SystemPlayerFocus?>.Binding

    var body: some View {
        HStack(spacing: LayoutMetrics.chipSpacing) {
            ForEach(tabs, id: \.self) { tab in
                Text(tab.titleKey)
                    .chipAppearance(
                        isSelected: isExpanded && selectedTab == tab,
                        isFocused: focus.wrappedValue == .tab(tab),
                    )
                    .focusable()
                    .focused(focus, equals: .tab(tab))
                    .accessibilityAddTraits(isExpanded && selectedTab == tab ? [.isButton, .isSelected] : .isButton)
            }
        }
        // Full width so focus can come down from anywhere on the timeline.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
    }
}

struct SystemPlayerTabContent: View {
    var tab: PlayerInfoTab
    var media: MediaItem
    var content: PlayerTabsContent
    var chapters: [MediaChapter]
    var position: Double
    var onSelectChapter: (MediaChapter) -> Void
    var onRestart: () -> Void
    var focus: FocusState<SystemPlayerFocus?>.Binding
    var onSelectQueueItem: (Int) -> Void
    var onClose: () -> Void

    var body: some View {
        switch tab {
        case .info:
            PlayerMediaInfoView(media: media, services: content.services, layout: .wide, summaryLineLimit: 4) {
                if PlayerRestartButton.isAvailable(at: position) {
                    PlayerRestartButton(action: onRestart)
                        .focused(focus, equals: .restart)
                }
            }
            .padding(28)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                Color.black.opacity(0.35),
                in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous),
            )
            .videoOverlayGlass(in: RoundedRectangle(
                cornerRadius: LayoutMetrics.overlayCornerRadius,
                style: .continuous,
            ))
            // The button sits on the far side of the card, out of line with the tabs above it.
            .focusSection()
        case .chapters:
            PlayerChapterTrayView(chapters: chapters, currentPosition: position, onSelect: onSelectChapter)
                .padding(.horizontal, -12)
        case .queue:
            if let services = content.services {
                PlayerQueueView(
                    items: content.queueItems,
                    currentIndex: content.queueCurrentIndex,
                    services: services,
                    layout: .carousel,
                    onSelect: onSelectQueueItem,
                    onClose: onClose,
                    showsCarouselHeader: false,
                    focusesCurrentItemOnAppear: false,
                )
                .padding(.horizontal, -28)
            }
        }
    }
}

extension PlayerTabsContent {
    func tabs(chapters: [MediaChapter]) -> [PlayerInfoTab] {
        var tabs: [PlayerInfoTab] = [.info]
        if chapters.count >= 2 {
            tabs.append(.chapters)
        }
        if showsQueue {
            tabs.append(.queue)
        }
        return tabs
    }
}
