import SwiftUI

/// Touch remote on the half of a foldable lying flat. It stays black until touched so nothing lights up under the
/// picture, then shows large tiles that are easy to hit without looking down.
struct PlayerTabletopControlsView: View {
    var media: MediaItem?
    var isVisible: Bool
    var isLocked: Bool
    var isPaused: Bool
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var playbackRate: Float
    var showsEndsAtTime: Bool
    var chapters: [MediaChapter]
    var showsChaptersOnTimeline: Bool
    var scrubPreview: PlayerScrubPreview?
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var skipMarkerTitle: String?
    var isSharePlay: Bool
    var sleepTimer: SleepTimer?
    var showsPictureInPicture: Bool
    var isPictureInPictureEnabled: Bool
    var showsSettingsIndicator: Bool
    var canShowInfo: Bool
    var canPlayNext: Bool
    var isLive: Bool
    var behindLiveSeconds: Double
    var canSwitchPreviousChannel: Bool
    var canSwitchNextChannel: Bool
    var actions: PlayerTabletopActions

    var body: some View {
        ZStack {
            Color.black
                .contentShape(Rectangle())
                .onTapGesture(perform: actions.onTapBackground)

            if isVisible {
                if isLocked {
                    unlockTile
                } else {
                    tiles
                }
            } else if !isLocked, let skipMarkerTitle {
                skipMarkerTile(title: skipMarkerTitle)
                    .frame(height: Metrics.skipMarkerHeight)
                    .padding(.horizontal, Metrics.padding)
            }
        }
        .environment(\.colorScheme, .dark)
    }

    private var tiles: some View {
        VStack(spacing: Metrics.spacing) {
            topRow
                .frame(height: Metrics.smallTileSide)

            transportRow
                .frame(minHeight: Metrics.transportMinHeight)

            if let skipMarkerTitle {
                skipMarkerTile(title: skipMarkerTitle)
                    .frame(height: Metrics.skipMarkerHeight)
            }

            progressTile
        }
        .padding(.horizontal, Metrics.padding)
        .padding(.top, Metrics.padding)
        .padding(.bottom, Metrics.bottomPadding)
        .transition(.opacity)
    }

    private var topRow: some View {
        HStack(spacing: Metrics.spacing) {
            iconTile(
                systemName: "xmark",
                accessibilityLabel: String(localized: "common.actions.close"),
                action: actions.onDismiss,
            )

            titleTile

            if canPlayNext {
                iconTile(
                    systemName: "forward.end.fill",
                    accessibilityLabel: String(localized: "player.controls.next"),
                    action: actions.onPlayNext,
                )
            }

            if showsPictureInPicture {
                iconTile(
                    systemName: "pip.enter",
                    accessibilityLabel: String(localized: "player.controls.pictureInPicture"),
                    action: actions.onStartPictureInPicture,
                )
                .disabled(!isPictureInPictureEnabled)
            }

            iconTile(
                systemName: "lock.open",
                accessibilityLabel: String(localized: "player.controls.touchLock.lock"),
                action: actions.onToggleLock,
            )

            iconTile(
                systemName: "gearshape",
                accessibilityLabel: String(localized: "settings.title"),
                action: actions.onShowSettings,
            )
            .overlay(alignment: .topTrailing) {
                if showsSettingsIndicator {
                    PlaybackOffsetIndicator()
                        .padding(8)
                }
            }
        }
    }

    private var titleTile: some View {
        Button(action: interacting(actions.onShowInfo)) {
            HStack(spacing: 10) {
                VStack(alignment: .leading, spacing: 2) {
                    if let title = media?.primaryLabel {
                        Text(title)
                            .font(.rowTitle)
                            .lineLimit(1)
                    }
                    if let subtitle = media?.episodeTitleLabel {
                        Text(subtitle)
                            .font(.cardMetadata)
                            .foregroundStyle(.textSecondary)
                            .lineLimit(1)
                    }
                }

                Spacer(minLength: 0)

                if isSharePlay {
                    Image(systemName: "shareplay")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(.textSecondary)
                        .accessibilityLabel(Text("sharePlay.badge"))
                }

                if let sleepTimer, sleepTimer.isActive {
                    SleepTimerBadge(sleepTimer: sleepTimer, mediaKind: media?.type)
                }

                if canShowInfo {
                    Image(systemName: "chevron.up")
                        .font(.footnote.weight(.bold))
                        .foregroundStyle(.textSecondary)
                }
            }
            .padding(.horizontal, 16)
        }
        .buttonStyle(.tile)
        .allowsHitTesting(canShowInfo)
    }

    private var transportRow: some View {
        HStack(spacing: Metrics.spacing) {
            if isLive {
                transportTile(
                    systemName: "chevron.left",
                    accessibilityLabel: String(localized: "livetv.player.previousChannel"),
                    action: actions.onPreviousChannel,
                )
                .disabled(!canSwitchPreviousChannel)
            } else {
                transportTile(
                    systemName: seekIconName(prefix: "gobackward", seconds: seekBackwardSeconds),
                    accessibilityLabel: String(localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"),
                    action: actions.onSeekBackward,
                )
            }

            transportTile(
                systemName: isPaused ? "play.fill" : "pause.fill",
                accessibilityLabel: isPaused
                    ? String(localized: "common.actions.play")
                    : String(localized: "common.actions.pause"),
                font: .system(size: 44, weight: .black),
                action: actions.onPlayPause,
            )

            if isLive {
                transportTile(
                    systemName: "chevron.right",
                    accessibilityLabel: String(localized: "livetv.player.nextChannel"),
                    action: actions.onNextChannel,
                )
                .disabled(!canSwitchNextChannel)
            } else {
                transportTile(
                    systemName: seekIconName(prefix: "goforward", seconds: seekForwardSeconds),
                    accessibilityLabel: String(localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)"),
                    action: actions.onSeekForward,
                )
            }
        }
    }

    @ViewBuilder
    private var progressTile: some View {
        if isLive {
            HStack {
                Group {
                    if behindLiveSeconds < 2 {
                        Text("livetv.player.live")
                    } else {
                        Text("livetv.player.behind \(Int(behindLiveSeconds / 60))")
                    }
                }
                .font(.rowTitle.monospacedDigit())
                .foregroundStyle(.textPrimary)

                Spacer()

                Button(
                    "livetv.player.goLive",
                    systemImage: "dot.radiowaves.left.and.right",
                    action: interacting(actions.onGoLive),
                )
                .actionButtonStyle(.primary)
                .disabled(behindLiveSeconds < 2)
            }
            .padding(12)
            .background(.surfaceRaised, in: tileShape)
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
                onEditingChanged: actions.onScrubbingChanged,
                floatsScrubDetails: true,
            )
            .padding(.vertical, 4)
            .background(.surfaceRaised, in: tileShape)
        }
    }

    private var unlockTile: some View {
        Button(action: interacting(actions.onToggleLock)) {
            VStack(spacing: 12) {
                Image(systemName: "lock.fill")
                    .font(.system(size: 34, weight: .semibold))
                Text("player.controls.touchLock.unlock")
                    .font(.rowTitle)
                    .multilineTextAlignment(.center)
            }
            .padding(.horizontal, 24)
        }
        .buttonStyle(.tile)
        .frame(width: Metrics.unlockTileSize.width, height: Metrics.unlockTileSize.height)
        .transition(.opacity)
    }

    private func skipMarkerTile(title: String) -> some View {
        Button(action: interacting(actions.onSkipMarker)) {
            HStack(spacing: 10) {
                Text(title)
                Image(systemName: "chevron.right")
                    .font(.footnote.weight(.bold))
            }
            .font(.rowTitle)
        }
        .buttonStyle(.tile(isProminent: true))
        .accessibilityLabel(title)
        .transition(.opacity)
    }

    private func iconTile(systemName: String, accessibilityLabel: String, action: @escaping () -> Void) -> some View {
        Button(action: interacting(action)) {
            Image(systemName: systemName)
                .font(.headline.weight(.semibold))
        }
        .buttonStyle(.tile)
        .frame(width: Metrics.smallTileSide)
        .accessibilityLabel(accessibilityLabel)
    }

    private func transportTile(
        systemName: String,
        accessibilityLabel: String,
        font: Font = .system(size: 30, weight: .bold),
        action: @escaping () -> Void,
    ) -> some View {
        Button(action: interacting(action)) {
            Image(systemName: systemName)
                .font(font)
        }
        .buttonStyle(.tile)
        .accessibilityLabel(accessibilityLabel)
    }

    /// Every touch keeps the tiles on screen for another few seconds.
    private func interacting(_ action: @escaping () -> Void) -> () -> Void {
        {
            actions.onInteraction()
            action()
        }
    }

    private var tileShape: RoundedRectangle {
        RoundedRectangle(cornerRadius: LayoutMetrics.tileCornerRadius, style: .continuous)
    }

    private func seekIconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}

struct PlayerTabletopActions {
    var onTapBackground: () -> Void
    var onInteraction: () -> Void
    var onDismiss: () -> Void
    var onShowInfo: () -> Void
    var onShowSettings: () -> Void
    var onStartPictureInPicture: () -> Void
    var onToggleLock: () -> Void
    var onPlayNext: () -> Void
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var onScrubbingChanged: (Bool) -> Void
    var onSkipMarker: () -> Void
    var onGoLive: () -> Void
    var onPreviousChannel: () -> Void
    var onNextChannel: () -> Void
}

private enum Metrics {
    static let padding: CGFloat = 16
    /// Clears the home indicator, since the controls half ignores the safe area.
    static let bottomPadding: CGFloat = 24
    static let spacing: CGFloat = 10
    static let smallTileSide: CGFloat = 56
    static let transportMinHeight: CGFloat = 72
    static let skipMarkerHeight: CGFloat = 56
    static let unlockTileSize = CGSize(width: 280, height: 160)
}
