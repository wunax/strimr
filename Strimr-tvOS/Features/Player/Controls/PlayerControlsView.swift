import SwiftUI

struct PlayerControlsView: View {
    var media: MediaItem?
    var isPaused: Bool
    var videoResolution: String?
    var videoFormatBadge: PlayerVideoFormatBadge?
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var playbackRate: Float
    var showsEndsAtTime: Bool
    var showsClock: Bool
    var isScrubbing: Bool
    var onShowAudioSettings: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowSpeedSettings: () -> Void
    var onShowSettings: () -> Void
    var sleepTimer: SleepTimer
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var scrubPreview: PlayerScrubPreview?
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var onScrubbingChanged: (Bool) -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var onUserInteraction: () -> Void
    var isSharePlay: Bool
    var hasInfoPanel: Bool
    var onShowInfoPanel: () -> Void
    var isLive: Bool
    var behindLiveSeconds: Double
    var onGoLive: () -> Void
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void
    var settingsControl: PlayerSettingsControl?
    var showsSubtitleOffsetIndicator = false
    var settingsFocusGeneration: Int
    var isShowingPanel: Bool
    @FocusState private var focusedControl: FocusTarget?
    /// Focus leaving a side panel falls on the nearest control, the full-width timeline, where a stray left or right
    /// press seeks. It stays out of reach until a button has taken the focus back.
    @State private var isTimelineFocusSuspended = false
    private var playbackBadges: [PlayerControlBadge] {
        var badges: [PlayerControlBadge] = []

        if let videoResolution {
            badges.append(
                PlayerControlBadge(
                    id: "resolution",
                    title: videoResolution,
                    systemImage: nil,
                ),
            )
        }

        if let videoFormatBadge {
            badges.append(
                PlayerControlBadge(
                    id: videoFormatBadge.id,
                    title: videoFormatBadge.title,
                    systemImage: "sparkles",
                ),
            )
        }

        return badges
    }

    var body: some View {
        VStack(spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    if let title = media?.primaryLabel {
                        Text(title)
                            .font(.sectionTitle)
                            .foregroundStyle(.textPrimary)
                            .lineLimit(2)
                    }

                    if let subtitle = media?.episodeTitleLabel {
                        Text(subtitle)
                            .font(.facts)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(2)
                    }

                    if isSharePlay {
                        PlayerBadge(String(localized: "sharePlay.badge"))
                    }
                }

                Spacer()

                SleepTimerBadge(sleepTimer: sleepTimer, mediaKind: media?.type)

                if showsClock {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.facts.monospacedDigit())
                            .foregroundStyle(.textPrimary)
                            .videoTextShadow()
                    }
                }
            }

            Spacer()

            if !isScrubbing {
                PlayerAuxiliaryControlsRow(
                    skipMarkerTitle: skipMarkerTitle,
                    onSkipMarker: onSkipMarker,
                    badges: playbackBadges,
                )
                .padding(.horizontal, 24)
            }

            if isLive {
                HStack {
                    if behindLiveSeconds < 2 {
                        Text("livetv.player.live").font(.headline.monospacedDigit())
                    } else {
                        Text("livetv.player.behind \(Int(behindLiveSeconds / 60))").font(.headline.monospacedDigit())
                    }
                    Spacer()
                    Button("livetv.player.goLive", systemImage: "dot.radiowaves.left.and.right", action: onGoLive)
                        .actionButtonStyle(.primary)
                        .disabled(behindLiveSeconds < 2)
                }
            } else {
                PlayerTimelineView(
                    position: $position,
                    duration: duration,
                    bufferedAhead: bufferedAhead,
                    playbackPosition: bufferBasePosition,
                    playbackRate: playbackRate,
                    showsEndsAtTime: showsEndsAtTime,
                    chapters: chapters,
                    showsChaptersOnTimeline: showsChaptersOnTimeline,
                    scrubPreview: scrubPreview,
                    onEditingChanged: onScrubbingChanged,
                )
                .disabled(isTimelineFocusSuspended)
            }

            ZStack {
                HStack(spacing: 42) {
                    PlayerSettingButton(
                        systemImage: "speaker.wave.2",
                        action: onShowAudioSettings,
                    )
                    .focused($focusedControl, equals: .audio)

                    PlayerSettingButton(
                        systemImage: "captions.bubble",
                        action: onShowSubtitleSettings,
                    )
                    .overlay(alignment: .topTrailing) {
                        if showsSubtitleOffsetIndicator {
                            PlaybackOffsetIndicator()
                                .scaleEffect(1.4)
                                .allowsHitTesting(false)
                        }
                    }
                    .focused($focusedControl, equals: .subtitle)

                    Spacer()
                }

                HStack(spacing: 48) {
                    if isLive {
                        PlayerIconButton(
                            systemName: "chevron.up",
                            accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                            action: onPreviousChannel,
                        )
                        .disabled(!canSwitchPreviousChannel)
                    }

                    PlayerIconButton(
                        systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                        accessibilityLabel: String(localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"),
                        action: onSeekBackward,
                    )

                    PlayPauseButton(isPaused: isPaused, action: onPlayPause)
                        .focused($focusedControl, equals: .playPause)

                    PlayerIconButton(
                        systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds),
                        accessibilityLabel: String(
                            localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)",
                        ),
                        action: onSeekForward,
                    )

                    if isLive {
                        PlayerIconButton(
                            systemName: "chevron.down",
                            accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                            action: onNextChannel,
                        )
                        .disabled(!canSwitchNextChannel)
                    }
                }

                HStack(spacing: 42) {
                    Spacer()

                    if !isLive {
                        PlayerSettingButton(
                            systemImage: "speedometer",
                            accessibilityLabel: String(localized: "player.settings.speed"),
                            action: onShowSpeedSettings,
                        )
                        .focused($focusedControl, equals: .speed)
                    }

                    PlayerSettingButton(
                        systemImage: "slider.horizontal.3",
                        accessibilityLabel: String(localized: "settings.title"),
                        action: onShowSettings,
                    )
                    .focused($focusedControl, equals: .settings)
                }
            }
            .overlay(alignment: .bottom) {
                if hasInfoPanel {
                    PlayerInfoPanelDisclosureIndicator()
                        .offset(y: 42)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.top, 28)
        .padding(.bottom, hasInfoPanel ? 44 : 28)
        .background {
            PlayerControlsBackground()
        }
        .onAppear {
            focusedControl = .playPause
        }
        .onChange(of: isShowingPanel, initial: true) { _, isShowing in
            if isShowing {
                isTimelineFocusSuspended = true
            }
        }
        .onChange(of: focusedControl) { _, control in
            guard let control, !isShowingPanel, isTimelineFocusSuspended else { return }
            isTimelineFocusSuspended = false
            // The system picks its own control once the panel is gone, after the restore below has already run.
            if let returningTarget, control != returningTarget {
                focusedControl = returningTarget
            }
        }
        .onChange(of: settingsFocusGeneration) { _, _ in
            DispatchQueue.main.async {
                if let returningTarget {
                    focusedControl = returningTarget
                }
            }
        }
        .onMoveCommand { direction in
            if direction == .down, hasInfoPanel {
                onShowInfoPanel()
            } else {
                onUserInteraction()
            }
        }
    }

    private var returningTarget: FocusTarget? {
        switch settingsControl {
        case .audio: .audio
        case .subtitle: .subtitle
        case .speed: .speed
        case .settings: .settings
        case nil: nil
        }
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

private struct PlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?
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

enum PlayerSettingsControl {
    case audio, subtitle, speed, settings
}

private enum FocusTarget: Hashable {
    case audio, subtitle, speed, settings
    case playPause
}
