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
    let onRestart: () -> Void
    let onClose: () -> Void
    /// Shown below the video on a foldable propped up like a laptop, on its own black half: no backdrop.
    var isEmbedded = false

    @FocusState private var focusedTarget: FocusTarget?
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
        .padding(.top, isEmbedded ? Metrics.embeddedTopPadding : Metrics.topPadding)
        .padding(.bottom, Metrics.bottomPadding)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
            if !isEmbedded {
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
        }
        .environment(\.colorScheme, .dark)
        #if os(tvOS)
            .onAppear {
                DispatchQueue.main.async {
                    focusedTarget = .tab(selectedTab)
                }
            }
            .onChange(of: focusedTarget) { previous, current in
                guard case let .tab(tab) = current else { return }
                // Going up from the restart button lands on the tab nearest to it, not on the open one.
                if previous == .restart, tab != selectedTab {
                    DispatchQueue.main.async {
                        focusedTarget = .tab(selectedTab)
                    }
                    return
                }
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
        HStack(spacing: LayoutMetrics.chipSpacing) {
            ForEach(tabs, id: \.self) { tab in
                tabButton(tab)
            }

            #if !os(tvOS)
                Spacer(minLength: 0)

                if PlayerRestartButton.isAvailable(at: currentPosition) {
                    compactRestartButton
                }

                Button(action: onClose) {
                    Image(systemName: "chevron.down")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.textPrimary)
                        .frame(width: 36, height: 30)
                        .background(.surfaceRaised, in: Capsule())
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
            Text(tab.titleKey)
                .chipAppearance(isSelected: isSelected, isFocused: focusedTarget == .tab(tab))
                .focusable()
                .focused($focusedTarget, equals: .tab(tab))
                .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
        #else
            Button {
                select(tab)
            } label: {
                Text(tab.titleKey)
            }
            .buttonStyle(.chip(isSelected: isSelected))
            .accessibilityAddTraits(isSelected ? .isSelected : [])
        #endif
    }

    private func select(_ tab: PlayerInfoTab) {
        guard tab != selectedTab else { return }
        withAnimation(Motion.crossfade) {
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
        ) {
            // Beside the details it would narrow the synopsis on a phone; there it sits in the tab bar instead.
            #if os(tvOS)
                if PlayerRestartButton.isAvailable(at: currentPosition) {
                    PlayerRestartButton(action: onRestart)
                        .focused($focusedTarget, equals: .restart)
                }
            #endif
        }
        .padding(.horizontal, Metrics.horizontalPadding)
        #if os(tvOS)
            // The button sits on the far side of the panel, out of line with the tabs above it.
            .focusSection()
        #endif
    }

    #if !os(tvOS)
        private var compactRestartButton: some View {
            Button(action: onRestart) {
                ViewThatFits(in: .horizontal) {
                    Label("common.actions.playFromStart", systemImage: "arrow.counterclockwise")
                        .padding(.horizontal, 12)
                    Image(systemName: "arrow.counterclockwise")
                        .frame(width: 36)
                }
                .font(.footnote.weight(.bold))
                .foregroundStyle(.textPrimary)
                .lineLimit(1)
                .frame(height: 30)
                .background(.surfaceRaised, in: Capsule())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(Text("common.actions.playFromStart"))
        }
    #endif

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

private enum FocusTarget: Hashable {
    case tab(PlayerInfoTab)
    case restart
}

struct PlayerInfoPanelDisclosureButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.up")
                .font(.caption.weight(.bold))
                .foregroundStyle(.textPrimary)
                .frame(width: 32, height: 22)
                .background(.surfaceRaised, in: Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(String(localized: "player.info.open"))
    }
}

struct PlayerInfoPanelDisclosureIndicator: View {
    var body: some View {
        Image(systemName: "chevron.down")
            .font(.caption.weight(.bold))
            .foregroundStyle(.textSecondary)
            .frame(width: 32, height: 22)
            .accessibilityHidden(true)
            .allowsHitTesting(false)
    }
}

private enum Metrics {
    #if os(tvOS)
        static let horizontalPadding: CGFloat = 80
        static let topPadding: CGFloat = 48
        static let embeddedTopPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 56
        static let sectionSpacing: CGFloat = 24
    #else
        static let horizontalPadding: CGFloat = 24
        static let topPadding: CGFloat = 28
        static let embeddedTopPadding: CGFloat = 8
        static let bottomPadding: CGFloat = 12
        static let sectionSpacing: CGFloat = 14
    #endif
}
