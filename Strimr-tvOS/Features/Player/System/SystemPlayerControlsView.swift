import SwiftUI

/// Player controls styled after the tvOS system player: a thin timeline at the bottom, the title above it, round
/// glass buttons on the right and tabs below.
struct SystemPlayerControlsView: View {
    var state: PlayerControlsState
    var actions: PlayerControlsActions
    @Binding var position: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: SystemPlayerFocus?
    @State private var presentedMenu: SystemPlayerMenu?
    @State private var lastFocusedButton: SystemPlayerButton?
    /// Focus leaving an adjustment bar or a panel falls on the full-width timeline, where a stray press would seek.
    /// The timeline stays out of reach until a button has taken the focus back.
    @State private var isTimelineFocusSuspended = false
    @State private var selectedTab = PlayerInfoTab.info
    /// Follows `isShowingTabs` through an explicit animation, so the focus can return to the timeline once it ends.
    @State private var areTabsExpanded = false

    private var isShowingTabs: Bool {
        state.isShowingTabs && state.tabs != nil
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            Spacer(minLength: 0)

            if !state.isScrubbing, !areTabsExpanded {
                titleRow
                    .padding(.bottom, 22)
                    .transition(.opacity)
            }

            if !areTabsExpanded {
                timeline
                    .transition(.opacity)
            }

            tabs
        }
        // The open menu keeps the focus; the controls under it stay out of reach until it closes.
        .disabled(presentedMenu != nil)
        .systemPlayerMenus(presentedMenu: $presentedMenu, sections: menuSections(for:))
        .padding(.horizontal, SystemPlayerMetrics.horizontalMargin)
        .padding(.top, SystemPlayerMetrics.topMargin)
        .padding(.bottom, SystemPlayerMetrics.bottomMargin)
        .background(alignment: .bottom) {
            SystemPlayerControlsBackground()
        }
        .ignoresSafeArea()
        .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: state.isScrubbing)
        .animation(Motion.animation(Motion.panel, reduceMotion: reduceMotion), value: presentedMenu)
        .onAppear {
            DispatchQueue.main.async {
                focus = initialFocus
            }
        }
        .onChange(of: isShowingTabs, initial: true) { _, isShowing in
            if !isShowing {
                // Opening the tabs suspended the timeline, which would leave the focus on the first tab.
                isTimelineFocusSuspended = false
            }
            withAnimation(Motion.animation(Motion.panel, reduceMotion: reduceMotion)) {
                areTabsExpanded = isShowing
            } completion: {
                // The timeline cannot take the focus while the tabs are still closing.
                if !isShowing, !isShowingTabs {
                    focus = initialFocus
                }
            }
            if isShowing {
                DispatchQueue.main.async {
                    if !focus.isTab {
                        focus = .tab(.info)
                    }
                }
            }
        }
        .onMoveCommand { _ in
            actions.userInteraction()
        }
        .onChange(of: focus) { previous, current in
            handleFocusChange(from: previous, to: current)
        }
        .onChange(of: state.isShowingPanel, initial: true) { _, isShowing in
            if isShowing {
                isTimelineFocusSuspended = true
            }
        }
        .onChange(of: state.settingsFocusGeneration) { _, _ in
            DispatchQueue.main.async {
                if let lastFocusedButton {
                    focus = .button(lastFocusedButton)
                }
            }
        }
        .onChange(of: presentedMenu) { previous, current in
            actions.menuPresentationChanged(current != nil)
            if current == nil, let previous {
                DispatchQueue.main.async {
                    focus = .button(.menu(previous))
                }
            }
        }
        .onDisappear {
            if presentedMenu != nil {
                actions.menuPresentationChanged(false)
            }
        }
    }

    private func menuSections(for menu: SystemPlayerMenu) -> [PlayerMenuSection] {
        state.menus?.sections(menu) ?? []
    }

    private func handleFocusChange(from previous: SystemPlayerFocus?, to current: SystemPlayerFocus?) {
        if case let .tab(tab) = current {
            if !state.isShowingTabs {
                // Only coming down from the controls opens the tabs. As they close, the focus engine falls back on
                // the first tab until the timeline can take it back, which must not reopen them. Restarting closes
                // them from the restart button.
                guard previous != nil, !previous.isTab, previous != .restart else { return }
                // Coming down from the full-width timeline lands on whichever tab is nearest the playhead; the tabs
                // always open on Info instead.
                selectedTab = .info
                actions.tabsPresentationChanged(true)
                if tab != .info {
                    DispatchQueue.main.async {
                        focus = .tab(.info)
                    }
                }
                return
            }
            // Going up from the restart button lands on the tab nearest to it, not on the open one.
            if previous == .restart, tab != selectedTab {
                DispatchQueue.main.async {
                    focus = .tab(selectedTab)
                }
                return
            }
            withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                selectedTab = tab
            }
        }
        if case let .button(id) = current {
            lastFocusedButton = id
            if !state.isShowingPanel {
                isTimelineFocusSuspended = false
            }
        }
    }

    /// Live TV has no timeline to land on: its buttons take the focus instead.
    private var initialFocus: SystemPlayerFocus {
        if state.live != nil {
            return .button(.channels)
        }
        return isShowingTabs ? .tab(.info) : .timeline
    }

    @ViewBuilder
    private var tabs: some View {
        if let content = state.tabs, let media = state.media {
            let tabs = content.tabs(chapters: state.chapters)
            VStack(alignment: .leading, spacing: 28) {
                SystemPlayerTabsRow(
                    tabs: tabs,
                    selectedTab: selectedTab,
                    isExpanded: areTabsExpanded,
                    focus: $focus,
                )
                .onMoveCommand { direction in
                    if direction == .up, isShowingTabs {
                        actions.tabsPresentationChanged(false)
                    }
                }

                if areTabsExpanded {
                    SystemPlayerTabContent(
                        tab: tabs.contains(selectedTab) ? selectedTab : .info,
                        media: media,
                        content: content,
                        chapters: state.chapters,
                        position: state.bufferBasePosition,
                        onSelectChapter: actions.selectChapter,
                        onRestart: actions.restartFromBeginning,
                        focus: $focus,
                        onSelectQueueItem: actions.selectQueueItem,
                        onClose: { actions.tabsPresentationChanged(false) },
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .padding(.top, areTabsExpanded ? 0 : 20)
            // Hidden rather than removed while scrubbing, so the timeline above keeps its place.
            .opacity(state.isScrubbing ? 0 : 1)
            .disabled(state.isScrubbing)
            .accessibilityHidden(state.isScrubbing)
            .onExitCommand(perform: isShowingTabs ? { actions.tabsPresentationChanged(false) } : nil)
        }
    }

    private var topRow: some View {
        HStack(spacing: 12) {
            Spacer()

            SleepTimerBadge(sleepTimer: state.sleepTimer, mediaKind: state.media?.type)

            if state.showsClock {
                TimelineView(.periodic(from: .now, by: 30)) { context in
                    Text(context.date.formatted(date: .omitted, time: .shortened))
                        .font(.facts.monospacedDigit())
                        .foregroundStyle(.textPrimary)
                        .videoTextShadow()
                }
            }
        }
    }

    private var titleRow: some View {
        HStack(alignment: .bottom, spacing: 32) {
            VStack(alignment: .leading, spacing: 10) {
                if state.live != nil || !eyebrowParts.isEmpty {
                    HStack(spacing: 14) {
                        if let live = state.live {
                            SystemPlayerLiveBadge(live: live)
                        }
                        Text(eyebrowParts.joined(separator: " · "))
                            .font(.bodyText.weight(.medium))
                            .foregroundStyle(.textPrimary)
                            .lineLimit(1)
                    }
                }

                if let title {
                    Text(title)
                        .font(.heroTitle)
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
                }
            }
            .videoTextShadow()
            .accessibilityElement(children: .combine)

            Spacer(minLength: 0)

            buttons
        }
        .focusSection()
    }

    @ViewBuilder
    private var buttons: some View {
        if state.menus != nil {
            HStack(spacing: 24) {
                if state.live != nil {
                    SystemPlayerActionButton(
                        systemImage: "list.bullet",
                        accessibilityLabel: String(localized: "livetv.player.channels"),
                        action: actions.showLiveChannels,
                    )
                    .focused($focus, equals: .button(.channels))
                }

                SystemPlayerMenuButton(
                    systemImage: "captions.bubble",
                    accessibilityLabel: String(localized: "player.settings.subtitles"),
                    menu: .subtitles,
                    presentedMenu: $presentedMenu,
                    showsIndicator: state.showsSubtitleOffsetIndicator,
                )
                .focused($focus, equals: .button(.menu(.subtitles)))

                SystemPlayerMenuButton(
                    systemImage: "waveform",
                    accessibilityLabel: String(localized: "player.settings.audio"),
                    menu: .audio,
                    presentedMenu: $presentedMenu,
                )
                .focused($focus, equals: .button(.menu(.audio)))

                SystemPlayerMenuButton(
                    systemImage: "ellipsis",
                    accessibilityLabel: String(localized: "settings.title"),
                    menu: .more,
                    presentedMenu: $presentedMenu,
                )
                .focused($focus, equals: .button(.menu(.more)))
            }
            .focusSection()
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if let live = state.live {
            if !LiveTVLiveBadge.isLive(behindLiveSeconds: live.behindLiveSeconds, isAtLiveEdge: live.isAtLiveEdge) {
                Button("livetv.player.goLive", systemImage: "dot.radiowaves.left.and.right", action: actions.goLive)
                    .actionButtonStyle(.secondary)
                    .focused($focus, equals: .button(.goLive))
                    // Spans the width so focus can come down to it from the buttons on the right.
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .focusSection()
            }
        } else {
            SystemPlayerTimelineView(
                position: $position,
                state: state,
                isFocused: focus == .timeline,
                onEditingChanged: actions.scrubbingChanged,
                onCancel: actions.scrubbingCancelled,
                onSeekBackward: actions.seekBackward,
                onSeekForward: actions.seekForward,
                onPlayPause: actions.playPause,
                onIdleSwipe: actions.userInteraction,
            )
            .focused($focus, equals: .timeline)
            .disabled(isTimelineFocusSuspended)
        }
    }

    /// Episodes show their show and number above the episode title, as the system does; movies only their badges.
    private var title: String? {
        guard let media = state.media else { return nil }
        if media.type == .episode, !media.title.trimmingCharacters(in: .whitespaces).isEmpty {
            return media.title
        }
        return media.primaryLabel
    }

    private var eyebrowParts: [String] {
        var parts: [String] = []
        if let media = state.media, media.type == .episode {
            parts.append(media.primaryLabel)
            if let number = media.tertiaryLabel {
                parts.append(number)
            }
        }
        parts += state.badges.map(\.title)
        if state.isSharePlay {
            parts.append(String(localized: "sharePlay.badge"))
        }
        return parts
    }
}

enum SystemPlayerFocus: Hashable {
    case timeline
    case button(SystemPlayerButton)
    case tab(PlayerInfoTab)
    case restart
}

enum SystemPlayerButton: Hashable {
    case channels
    case goLive
    case menu(SystemPlayerMenu)
}

private extension SystemPlayerFocus? {
    var isTab: Bool {
        if case .tab = self {
            true
        } else {
            false
        }
    }
}

enum SystemPlayerMetrics {
    static let horizontalMargin: CGFloat = 80
    static let topMargin: CGFloat = 50
    static let bottomMargin: CGFloat = 48
}

/// Contextual action of the system style, such as "Skip Intro": a white capsule at the bottom right, shown while the
/// controls are hidden, as in the system player.
struct SystemPlayerContextualAction: View {
    var title: String
    var action: () -> Void

    var body: some View {
        Button(title, action: action)
            .font(.bodyText.weight(.semibold))
            .actionButtonStyle(.primary)
            .padding(.trailing, SystemPlayerMetrics.horizontalMargin)
            .padding(.bottom, SystemPlayerMetrics.bottomMargin)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomTrailing)
            .ignoresSafeArea()
    }
}

/// Red "LIVE" capsule at the live edge, how far behind otherwise, as the system player shows it before the title.
private struct SystemPlayerLiveBadge: View {
    var live: PlayerLiveState

    var body: some View {
        let isLive = LiveTVLiveBadge.isLive(behindLiveSeconds: live.behindLiveSeconds, isAtLiveEdge: live.isAtLiveEdge)
        Group {
            if isLive {
                Text("livetv.player.live")
                    .textCase(.uppercase)
            } else {
                Text("livetv.player.behindShort \(max(1, Int((live.behindLiveSeconds / 60).rounded())))")
                    .monospacedDigit()
            }
        }
        .font(.badge)
        .foregroundStyle(.textPrimary)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(isLive ? Color.liveIndicator : .surfaceRaised, in: Capsule(style: .continuous))
    }
}

/// Darkens the lower part of the video only, where the system style draws its controls.
private struct SystemPlayerControlsBackground: View {
    var body: some View {
        LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black.opacity(0.45), location: 0.55),
                .init(color: .black.opacity(0.7), location: 1),
            ],
            startPoint: .top,
            endPoint: .bottom,
        )
        .frame(height: 520)
        .frame(maxWidth: .infinity)
        .allowsHitTesting(false)
    }
}
