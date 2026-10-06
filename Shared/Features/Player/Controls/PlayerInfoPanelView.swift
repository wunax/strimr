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
    #if os(iOS)
        @Environment(\.horizontalSizeClass) private var horizontalSizeClass
        @Environment(\.verticalSizeClass) private var verticalSizeClass
    #endif

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
        VStack(alignment: .leading, spacing: Metrics.sectionSpacing) {
            tabBar
                .padding(.horizontal, Metrics.horizontalPadding)

            content
        }
        .padding(.top, Metrics.topPadding)
        .padding(.bottom, Metrics.bottomPadding)
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
        #if os(tvOS)
            .onAppear {
                DispatchQueue.main.async {
                    focusedTab = selectedTab
                }
            }
            .onChange(of: focusedTab) { _, tab in
                guard let tab else { return }
                select(tab)
            }
        #else
            .contentShape(Rectangle())
            .simultaneousGesture(
                DragGesture(minimumDistance: 20).onEnded { value in
                    let translation = value.translation
                    if translation.height > 60, abs(translation.height) > abs(translation.width) {
                        onClose()
                    }
                },
            )
        #endif
    }

    private var tabBar: some View {
        HStack(spacing: Metrics.tabSpacing) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }

            #if !os(tvOS)
                Spacer(minLength: 0)

                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.white.opacity(0.85))
                        .frame(width: 36, height: 30)
                        .background(.white.opacity(0.12), in: Capsule())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(Text("common.actions.close"))
            #endif
        }
        // Full width so focus can move up into the tabs from anywhere below them.
        .frame(maxWidth: .infinity, alignment: .leading)
        #if os(tvOS)
            .focusSection()
            .onMoveCommand { direction in
                if direction == .up {
                    onClose()
                }
            }
        #endif
    }

    @ViewBuilder
    private func tabButton(_ tab: PlayerInfoTab) -> some View {
        let isSelected = selectedTab == tab
        #if os(tvOS)
            let isFocused = focusedTab == tab
            tabLabel(tab, isHighlighted: isFocused, isSelected: isSelected)
                .scaleEffect(isFocused ? 1.05 : 1)
                .focusable()
                .focused($focusedTab, equals: tab)
                .animation(.easeOut(duration: 0.16), value: isFocused)
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        #else
            Button {
                select(tab)
            } label: {
                tabLabel(tab, isHighlighted: isSelected, isSelected: isSelected)
            }
            .buttonStyle(.plain)
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }

    private func tabLabel(_ tab: PlayerInfoTab, isHighlighted: Bool, isSelected: Bool) -> some View {
        Text(tab.titleKey)
            .font(Metrics.tabFont)
            .foregroundStyle(isHighlighted ? .black : .white.opacity(isSelected ? 1 : 0.6))
            .padding(.horizontal, Metrics.tabHorizontalPadding)
            .padding(.vertical, Metrics.tabVerticalPadding)
            .background(
                Capsule(style: .continuous)
                    .fill(isHighlighted ? .white : .white.opacity(isSelected ? 0.18 : 0)),
            )
            .contentShape(Capsule(style: .continuous))
    }

    private func select(_ tab: PlayerInfoTab) {
        guard tab != selectedTab else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            selectedTab = tab
        }
    }

    @ViewBuilder
    private var content: some View {
        switch selectedTab {
        case .info:
            infoContent
                .transition(.opacity)
        case .chapters:
            PlayerChapterTrayView(
                chapters: chapters,
                currentPosition: currentPosition,
                onSelect: onSelectChapter,
            )
            .padding(.horizontal, max(0, Metrics.horizontalPadding - 12))
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
                .padding(.horizontal, max(0, Metrics.horizontalPadding - 28))
                .transition(.opacity)
            }
        }
    }

    @ViewBuilder
    private var infoContent: some View {
        #if os(tvOS)
            mediaInfo(layout: .wide, summaryLineLimit: 4)
        #else
            // Scrolls only when the synopsis does not fit the height left by the video.
            ViewThatFits(in: .vertical) {
                mediaInfo(layout: infoLayout, summaryLineLimit: nil)
                ScrollView {
                    mediaInfo(layout: infoLayout, summaryLineLimit: nil)
                }
                .scrollIndicators(.hidden)
            }
        #endif
    }

    private func mediaInfo(layout: PlayerMediaInfoLayout, summaryLineLimit: Int?) -> some View {
        PlayerMediaInfoView(
            media: media,
            services: services,
            layout: layout,
            summaryLineLimit: summaryLineLimit,
        )
        .padding(.horizontal, Metrics.horizontalPadding)
    }

    #if os(iOS)
        private var infoLayout: PlayerMediaInfoLayout {
            horizontalSizeClass == .compact && verticalSizeClass == .regular ? .stacked : .wide
        }
    #elseif os(macOS)
        private var infoLayout: PlayerMediaInfoLayout {
            .wide
        }
    #endif
}

struct PlayerInfoPanelDisclosureButton: View {
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
        .accessibilityLabel(String(localized: "player.info.open"))
    }
}

struct PlayerInfoPanelDisclosureIndicator: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(.white.opacity(0.65))
            .frame(width: 32, height: 22)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private enum Metrics {
    #if os(tvOS)
        static let horizontalPadding: CGFloat = 80
        static let topPadding: CGFloat = 48
        static let bottomPadding: CGFloat = 56
        static let sectionSpacing: CGFloat = 24
        static let tabSpacing: CGFloat = 16
        static let tabFont = Font.callout.weight(.semibold)
        static let tabHorizontalPadding: CGFloat = 28
        static let tabVerticalPadding: CGFloat = 12
    #else
        static let horizontalPadding: CGFloat = 24
        static let topPadding: CGFloat = 28
        static let bottomPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 14
        static let tabSpacing: CGFloat = 8
        static let tabFont = Font.subheadline.weight(.semibold)
        static let tabHorizontalPadding: CGFloat = 14
        static let tabVerticalPadding: CGFloat = 7
    #endif
}
