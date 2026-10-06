import SwiftUI

enum PlayerInfoTab: Hashable {
    case info
    case chapters
    case queue

    var titleKey: LocalizedStringKey {
        switch self {
        case .info: "player.info.title"
        case .chapters: "player.chapters.title"
        case .queue: "player.queue.title"
        }
    }
}

struct PlayerInfoPanelView: View {
    let media: MediaItem
    let services: MediaServices?
    let queueItems: [PlaybackQueueItem]
    let queueCurrentIndex: Int
    let showsQueue: Bool
    let chapters: [MediaChapter]
    let currentPosition: Double
    @Binding var selectedTab: PlayerInfoTab
    let onSelectQueueItem: (Int) -> Void
    let onSelectChapter: (MediaChapter) -> Void
    let onClose: () -> Void

    @FocusState private var focusedTab: PlayerInfoTab?

    private var tabs: [PlayerInfoTab] {
        var tabs: [PlayerInfoTab] = [.info]
        if chapters.count >= 2 {
            tabs.append(.chapters)
        }
        if showsQueue {
            tabs.append(.queue)
        }
        return tabs
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            tabBar
                .padding(.horizontal, 80)

            content
        }
        .padding(.top, 48)
        .padding(.bottom, 56)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            LinearGradient(
                stops: [
                    .init(color: .clear, location: 0),
                    .init(color: .black.opacity(0.75), location: 0.25),
                    .init(color: .black.opacity(0.9), location: 1),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .ignoresSafeArea()
            .allowsHitTesting(false)
        }
        .environment(\.colorScheme, .dark)
        .onAppear {
            DispatchQueue.main.async {
                focusedTab = selectedTab
            }
        }
        .onChange(of: focusedTab) { _, tab in
            guard let tab, tab != selectedTab else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                selectedTab = tab
            }
        }
    }

    private var tabBar: some View {
        HStack(spacing: 16) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }
        }
        // Full width so focus can move up into the tabs from anywhere below them.
        .frame(maxWidth: .infinity, alignment: .leading)
        .focusSection()
        .onMoveCommand { direction in
            if direction == .up {
                onClose()
            }
        }
    }

    private func tabButton(_ tab: PlayerInfoTab) -> some View {
        let isFocused = focusedTab == tab
        let isSelected = selectedTab == tab

        return Text(tab.titleKey)
            .font(.callout.weight(.semibold))
            .foregroundStyle(isFocused ? .black : .white.opacity(isSelected ? 1 : 0.6))
            .padding(.horizontal, 28)
            .padding(.vertical, 12)
            .background(
                Capsule(style: .continuous)
                    .fill(isFocused ? .white : .white.opacity(isSelected ? 0.18 : 0)),
            )
            .scaleEffect(isFocused ? 1.05 : 1)
            .contentShape(Capsule(style: .continuous))
            .focusable()
            .focused($focusedTab, equals: tab)
            .animation(.easeOut(duration: 0.16), value: isFocused)
            .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .info:
            PlayerMediaInfoView(
                media: media,
                services: services,
                layout: .wide,
                summaryLineLimit: 4,
            )
            .padding(.horizontal, 80)
            .transition(.opacity)
        case .chapters:
            PlayerChapterTrayView(
                chapters: chapters,
                currentPosition: currentPosition,
                onSelect: onSelectChapter,
            )
            .padding(.horizontal, 68)
            .transition(.opacity)
        case .queue:
            if let services {
                PlayerQueueView(
                    items: queueItems,
                    currentIndex: queueCurrentIndex,
                    services: services,
                    layout: .carousel,
                    onSelect: onSelectQueueItem,
                    onClose: onClose,
                    showsCarouselHeader: false,
                    focusesCurrentItemOnAppear: false,
                )
                .padding(.horizontal, 52)
                .transition(.opacity)
            }
        }
    }
}
