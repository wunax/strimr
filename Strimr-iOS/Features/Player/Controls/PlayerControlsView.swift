import SwiftUI

struct PlayerControlsView: View {
    var media: MediaItem?
    var isPaused: Bool
    var isBuffering: Bool
    var videoResolution: String?
    var videoFormatBadge: PlayerVideoFormatBadge?
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var playbackRate: Float
    var showsEndsAtTime: Bool
    var isScrubbing: Bool
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var scrubPreview: PlayerScrubPreview?
    var onShowChapters: () -> Void
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var onScrubbingChanged: (Bool) -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var isRotationLocked: Bool
    var onToggleRotationLock: () -> Void
    var isSharePlay: Bool
    var showsPictureInPicture: Bool
    var isPictureInPictureEnabled: Bool
    var onStartPictureInPicture: () -> Void
    var hasQueue: Bool
    var onShowQueue: () -> Void
    var isLive: Bool
    var behindLiveSeconds: Double
    var onGoLive: () -> Void
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void
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
        ZStack {
            VStack(spacing: 0) {
                PlayerControlsHeader(
                    media: media,
                    onDismiss: onDismiss,
                    onShowSettings: onShowSettings,
                    showsChapters: chapters.count >= 2,
                    onShowChapters: onShowChapters,
                    isSharePlay: isSharePlay,
                    showsPictureInPicture: showsPictureInPicture,
                    isPictureInPictureEnabled: isPictureInPictureEnabled,
                    onStartPictureInPicture: onStartPictureInPicture,
                )

                Spacer(minLength: 0)

                VStack(spacing: 18) {
                    PlayerAuxiliaryControlsRow(
                        isRotationLocked: isRotationLocked,
                        onToggleRotationLock: onToggleRotationLock,
                        skipMarkerTitle: skipMarkerTitle,
                        onSkipMarker: onSkipMarker,
                        badges: playbackBadges,
                    )
                    .padding(.horizontal, 24)
                    .opacity(isScrubbing ? 0 : 1)
                    .allowsHitTesting(!isScrubbing)

                    if isLive {
                        HStack {
                            if behindLiveSeconds < 2 {
                                Text("livetv.player.live").font(.headline.monospacedDigit())
                            } else {
                                Text("livetv.player.behind \(Int(behindLiveSeconds / 60))")
                                    .font(.headline.monospacedDigit())
                            }
                            Spacer()
                            Button(
                                "livetv.player.goLive",
                                systemImage: "dot.radiowaves.left.and.right",
                                action: onGoLive,
                            )
                            .buttonStyle(.borderedProminent)
                            .disabled(behindLiveSeconds < 2)
                        }
                        .foregroundStyle(.white)
                        .padding(.horizontal, 12)
                    } else {
                        ZStack(alignment: .bottom) {
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

                            if hasQueue {
                                PlayerQueueDisclosureButton(action: onShowQueue)
                                    .opacity(isScrubbing ? 0 : 1)
                                    .allowsHitTesting(!isScrubbing)
                                    .offset(y: 18)
                            }
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .padding(.horizontal, 20)
            .padding(.vertical, 16)

            PrimaryControls(
                isPaused: isPaused,
                onSeekBackward: onSeekBackward,
                onPlayPause: onPlayPause,
                onSeekForward: onSeekForward,
                seekBackwardSeconds: seekBackwardSeconds,
                seekForwardSeconds: seekForwardSeconds,
                isLive: isLive,
                canSwitchPreviousChannel: canSwitchPreviousChannel,
                canSwitchNextChannel: canSwitchNextChannel,
                onPreviousChannel: onPreviousChannel,
                onNextChannel: onNextChannel,
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background {
            PlayerControlsBackground()
        }
    }
}

private struct PlayerControlBadge: Identifiable {
    var id: String
    var title: String
    var systemImage: String?
}

private struct PlayerAuxiliaryControlsRow: View {
    var isRotationLocked: Bool
    var onToggleRotationLock: () -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var badges: [PlayerControlBadge]

    var body: some View {
        HStack(alignment: .bottom, spacing: 16) {
            RotationLockButton(isLocked: isRotationLocked, action: onToggleRotationLock)

            Spacer(minLength: 12)

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
            .frame(maxWidth: .infinity, alignment: .trailing)
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

private struct PlayerControlsHeader: View {
    var media: MediaItem?
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var showsChapters: Bool
    var onShowChapters: () -> Void
    var isSharePlay: Bool
    var showsPictureInPicture: Bool
    var isPictureInPictureEnabled: Bool
    var onStartPictureInPicture: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Button(action: onDismiss) {
                Image(systemName: "chevron.backward")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1),
                    )
            }

            VStack(alignment: .leading, spacing: 4) {
                if let title = media?.primaryLabel {
                    Text(title)
                        .font(.title3.weight(.semibold))
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

            if showsPictureInPicture {
                PlayerPictureInPictureButton(action: onStartPictureInPicture)
                    .disabled(!isPictureInPictureEnabled)
            }

            if showsChapters {
                PlayerChaptersButton(action: onShowChapters)
            }

            PlayerSettingsButton(action: onShowSettings)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }
}

private struct PrimaryControls: View {
    var isPaused: Bool
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var isLive: Bool
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void

    var body: some View {
        Group {
            if isLive {
                ZStack {
                    HStack {
                        PlayerIconButton(
                            systemName: "chevron.left",
                            accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                            action: onPreviousChannel,
                        )
                        .disabled(!canSwitchPreviousChannel)

                        Spacer()

                        PlayerIconButton(
                            systemName: "chevron.right",
                            accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                            action: onNextChannel,
                        )
                        .disabled(!canSwitchNextChannel)
                    }

                    transportControls
                }
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 12)
            } else {
                transportControls
            }
        }
        .padding(.bottom, 4)
    }

    private var transportControls: some View {
        HStack(spacing: 26) {
            PlayerIconButton(
                systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                accessibilityLabel: String(localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"),
                action: onSeekBackward,
            )

            PlayPauseButton(isPaused: isPaused, action: onPlayPause)

            PlayerIconButton(
                systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds),
                accessibilityLabel: String(localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)"),
                action: onSeekForward,
            )
        }
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
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
            .frame(height: 180)

            Spacer()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.7),
                ],
                startPoint: .top,
                endPoint: .bottom,
            )
            .frame(height: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}
