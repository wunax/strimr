import SwiftUI

struct PlayerControlsView: View {
    var media: MediaItem?
    var isPaused: Bool
    var isBuffering: Bool
    var supportsHDR: Bool
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var isScrubbing: Bool
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
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
    var isWatchTogether: Bool

    var body: some View {
        ZStack {
            VStack(spacing: 0) {
                PlayerControlsHeader(
                    media: media,
                    onDismiss: onDismiss,
                    onShowSettings: onShowSettings,
                    isWatchTogether: isWatchTogether,
                )

                Spacer(minLength: 0)

                VStack(spacing: 18) {
                    HStack {
                        RotationLockButton(isLocked: isRotationLocked, action: onToggleRotationLock)
                        Spacer()
                        if let skipMarkerTitle, let onSkipMarker {
                            SkipMarkerButton(title: skipMarkerTitle, action: onSkipMarker)
                        }
                    }
                    .padding(.horizontal, 24)
                    .opacity(isScrubbing ? 0 : 1)
                    .allowsHitTesting(!isScrubbing)

                    PlayerTimelineView(
                        position: $position,
                        duration: duration,
                        bufferedAhead: bufferedAhead,
                        playbackPosition: bufferBasePosition,
                        supportsHDR: supportsHDR,
                        onEditingChanged: onScrubbingChanged,
                    )
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
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        }
        .background {
            PlayerControlsBackground()
        }
    }
}

private struct PlayerControlsHeader: View {
    var media: MediaItem?
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var isWatchTogether: Bool

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

                if isWatchTogether {
                    Text("watchTogether.badge")
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

    var body: some View {
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
        .padding(.bottom, 4)
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
