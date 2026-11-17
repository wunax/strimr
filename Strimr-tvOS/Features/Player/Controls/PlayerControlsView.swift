import SwiftUI

struct PlayerControlsView: View {
    var state: PlayerControlsState
    var actions: PlayerControlsActions
    @Binding var position: Double
    @FocusState private var focusedControl: FocusTarget?
    /// Focus leaving a side panel falls on the nearest control, the full-width timeline, where a stray left or right
    /// press seeks. It stays out of reach until a button has taken the focus back.
    @State private var isTimelineFocusSuspended = false

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = state.media?.primaryLabel {
                        Text(title)
                            .font(.sectionTitle)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                    }

                    if let subtitle = state.media?.episodeTitleLabel {
                        Text(subtitle)
                            .font(.facts)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(2)
                    }

                    if state.isSharePlay {
                        PlayerBadge(String(localized: "sharePlay.badge"))
                    }
                }

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

            Spacer()

            if !state.isScrubbing {
                PlayerAuxiliaryControlsRow(
                    skipMarkerTitle: state.skipMarkerTitle,
                    onSkipMarker: actions.skipMarker,
                    badges: state.badges,
                )
                .padding(.horizontal, 24)
            }

            if let live = state.live {
                LiveTVPlayerStatusRow(
                    behindLiveSeconds: live.behindLiveSeconds,
                    isAtLiveEdge: live.isAtLiveEdge,
                    onGoLive: actions.goLive,
                )
            } else {
                PlayerTimelineView(
                    position: $position,
                    duration: state.duration,
                    bufferedAhead: state.bufferedAhead,
                    playbackPosition: state.bufferBasePosition,
                    playbackRate: state.playbackRate,
                    showsEndsAtTime: state.showsEndsAtTime,
                    chapters: state.chapters,
                    showsChaptersOnTimeline: state.showsChaptersOnTimeline,
                    skipSegments: state.skipSegments,
                    scrubPreview: state.scrubPreview,
                    onEditingChanged: actions.scrubbingChanged,
                    onCancel: actions.scrubbingCancelled,
                    swipesScrub: state.isPaused,
                    onIdleSwipe: actions.userInteraction,
                )
                .disabled(isTimelineFocusSuspended)
            }

            ZStack {
                HStack(spacing: 42) {
                    PlayerSettingButton(
                        systemImage: "speaker.wave.2",
                        action: actions.showAudioSettings,
                    )
                    .focused($focusedControl, equals: .audio)

                    PlayerSettingButton(
                        systemImage: "captions.bubble",
                        action: actions.showSubtitleSettings,
                    )
                    .overlay(alignment: .topTrailing) {
                        if state.showsSubtitleOffsetIndicator {
                            PlaybackOffsetIndicator()
                                .scaleEffect(1.4)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($focusedControl, equals: .subtitle)

                    Spacer()
                }

                HStack(spacing: 48) {
                    if let live = state.live {
                        PlayerIconButton(
                            systemName: "chevron.up",
                            accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                            action: actions.previousChannel,
                        )
                        .disabled(!live.canSwitchPreviousChannel)
                    }

                    PlayerIconButton(
                        systemName: state.seekBackwardSymbol,
                        accessibilityLabel: String(
                            localized: "player.controls.rewindSeconds \(state.seekBackwardSeconds)",
                        ),
                        action: actions.seekBackward,
                    )

                    PlayPauseButton(isPaused: state.isPaused, action: actions.playPause)
                        .focused($focusedControl, equals: .playPause)

                    PlayerIconButton(
                        systemName: state.seekForwardSymbol,
                        accessibilityLabel: String(
                            localized: "player.controls.skipForwardSeconds \(state.seekForwardSeconds)",
                        ),
                        action: actions.seekForward,
                    )

                    if let live = state.live {
                        PlayerIconButton(
                            systemName: "chevron.down",
                            accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                            action: actions.nextChannel,
                        )
                        .disabled(!live.canSwitchNextChannel)
                    }
                }

                HStack(spacing: 42) {
                    Spacer()

                    if state.live != nil {
                        PlayerSettingButton(
                            systemImage: "list.bullet.rectangle",
                            accessibilityLabel: String(localized: "livetv.player.channels"),
                            action: actions.showLiveChannels,
                        )
                    }

                    if state.live == nil {
                        PlayerSettingButton(
                            systemImage: "speedometer",
                            accessibilityLabel: String(localized: "player.settings.speed"),
                            action: actions.showSpeedSettings,
                        )
                        .focused($focusedControl, equals: .speed)
                    }

                    PlayerSettingButton(
                        systemImage: "slider.horizontal.3",
                        accessibilityLabel: String(localized: "settings.title"),
                        action: actions.showSettings,
                    )
                    .focused($focusedControl, equals: .settings)
                }
            }
            .overlay(alignment: .bottom) {
                if state.hasInfoPanel {
                    PlayerInfoPanelDisclosureIndicator()
                        .offset(y: 42)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, state.hasInfoPanel ? 44 : 28)
        .background {
            PlayerControlsBackground()
        }
        .onAppear {
            focusedControl = .playPause
        }
        .onChange(of: state.isShowingPanel, initial: true) { _, isShowing in
            if isShowing {
                isTimelineFocusSuspended = true
            }
        }
        .onChange(of: focusedControl) { _, control in
            guard let control, !state.isShowingPanel, isTimelineFocusSuspended else { return }
            isTimelineFocusSuspended = false
            // The system picks its own control once the panel is gone, after the restore below has already run.
            if let returningTarget, control != returningTarget {
                focusedControl = returningTarget
            }
        }
        .onChange(of: state.settingsFocusGeneration) { _, _ in
            DispatchQueue.main.async {
                if let returningTarget {
                    focusedControl = returningTarget
                }
            }
        }
        .onMoveCommand { direction in
            if direction == .down, state.hasInfoPanel {
                actions.showInfoPanel()
            } else {
                actions.userInteraction()
            }
        }
    }

    private var returningTarget: FocusTarget? {
        switch state.settingsControl {
        case .audio: .audio
        case .subtitle: .subtitle
        case .speed: .speed
        case .settings: .settings
        case nil: nil
        }
    }
}

private struct PlayerAuxiliaryControlsRow: View {
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var badges: [PlayerControlBadge]

    var body: some View {
        HStack {
            Spacer()
            VStack(alignment: .trailing, spacing: 8) {
                if hasSkipMarker {
                    if !badges.isEmpty {
                        badgesRow
                    }
                    if let skipMarkerTitle, let onSkipMarker {
                        SkipMarkerButton(title: skipMarkerTitle, action: onSkipMarker)
                    }
                } else if !badges.isEmpty {
                    badgesRow
                }
            }
        }
    }

    private var hasSkipMarker: Bool {
        skipMarkerTitle != nil && onSkipMarker != nil
    }

    private var badgesRow: some View {
        HStack(spacing: 8) {
            ForEach(badges) { badge in
                PlayerBadge(badge.title, systemImage: badge.systemImage)
            }
        }
    }
}

private enum FocusTarget: Hashable {
    case audio, subtitle, speed, settings
    case playPause
}
