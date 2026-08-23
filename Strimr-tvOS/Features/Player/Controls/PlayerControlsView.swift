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
    var onShowQualitySettings: () -> Void
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var scrubPreview: PlayerScrubPreview?
    var currentPosition: Double
    var isShowingChapterTray: Bool
    var onShowChapters: () -> Void
    var onSelectChapter: (MediaChapter) -> Void
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
    var hasQueue: Bool
    var onShowQueue: () -> Void
    var isLive: Bool
    var behindLiveSeconds: Double
    var onGoLive: () -> Void
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void
    @FocusState private var focusedControl: FocusTarget?
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
                            .font(.title2.weight(.semibold))
                            .foregroundStyle(.white)
                            .lineLimit(2)
                    }

                    if let subtitle = media?.tertiaryLabel {
                        Text(subtitle)
                            .font(.callout)
                            .foregroundStyle(.white.opacity(0.8))
                            .lineLimit(2)
                    }

                    if isSharePlay {
                        Text("sharePlay.badge")
                            .font(.caption.weight(.semibold))
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule(style: .continuous)
                                    .fill(Color.white.opacity(0.15)),
                            )
                            .foregroundStyle(.white.opacity(0.9))
                    }
                }

                Spacer()

                if showsClock {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        Text(context.date.formatted(date: .omitted, time: .shortened))
                            .font(.title3.monospacedDigit())
                            .foregroundStyle(.white.opacity(0.9))
                            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    }
                }
            }

            Spacer()

            if isShowingChapterTray {
                PlayerChapterTrayView(
                    chapters: chapters,
                    currentPosition: currentPosition,
                    onSelect: onSelectChapter,
                )
                .transition(.opacity.combined(with: .move(edge: .bottom)))
            }

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
                        .buttonStyle(.borderedProminent)
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
            }

            ZStack {
                HStack(spacing: 42) {
                    PlayerSettingButton(
                        systemImage: "speaker.wave.2",
                        action: onShowAudioSettings,
                    )

                    PlayerSettingButton(
                        systemImage: "captions.bubble",
                        action: onShowSubtitleSettings,
                    )

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

                        PlayerSettingButton(
                            systemImage: "gauge.with.dots.needle.33percent",
                            accessibilityLabel: String(localized: "player.settings.quality"),
                            action: onShowQualitySettings,
                        )
                    }

                    if chapters.count >= 2 {
                        PlayerSettingButton(
                            systemImage: "list.bullet.rectangle",
                            accessibilityLabel: String(localized: "player.chapters.title"),
                            action: onShowChapters,
                        )
                        .focused($focusedControl, equals: .chapters)
                    }
                }
            }
            .overlay(alignment: .bottom) {
                if hasQueue, !isShowingChapterTray {
                    PlayerQueueDisclosureIndicator()
                        .offset(y: 26)
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background {
            PlayerControlsBackground()
        }
        .onAppear {
            focusedControl = .playPause
        }
        .onChange(of: isShowingChapterTray) { _, isShowing in
            DispatchQueue.main.async {
                focusedControl = isShowing ? nil : .chapters
            }
        }
        .onMoveCommand { direction in
            if direction == .down, hasQueue, !isShowingChapterTray {
                onShowQueue()
            } else {
                onUserInteraction()
            }
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

private enum FocusTarget: Hashable {
    case playPause
    case chapters
}

private struct PlayerControlsBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .clear,
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .frame(height: 200)

            Spacer()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .frame(height: 280)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
