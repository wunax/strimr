import SwiftUI

struct PlayerControlsView: View {
    var media: MediaItem?
    var isPaused: Bool
    var isBuffering: Bool
    var supportsHDR: Bool
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var onDismiss: () -> Void
    var onShowSettings: () -> Void
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var onScrubbingChanged: (Bool) -> Void

    var body: some View {
        ZStack {
            VStack(spacing: 18) {
                PlayerControlsHeader(
                    media: media,
                    onDismiss: onDismiss,
                    onShowSettings: onShowSettings
                )

                Spacer()

                PrimaryControls(
                    isPaused: isPaused,
                    onSeekBackward: onSeekBackward,
                    onPlayPause: onPlayPause,
                    onSeekForward: onSeekForward
                )

                Spacer()
                
                PlayerTimelineView(
                    position: $position,
                    duration: duration,
                    bufferedAhead: bufferedAhead,
                    supportsHDR: supportsHDR,
                    onEditingChanged: onScrubbingChanged
                )
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
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
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
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
            }

            Spacer()

            Button(action: onShowSettings) {
                Image(systemName: "gearshape")
                    .font(.headline.weight(.semibold))
                    .foregroundStyle(.white)
                    .frame(width: 42, height: 42)
                    .background(.white.opacity(0.12), in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(Color.white.opacity(0.18), lineWidth: 1)
                    )
            }
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

    var body: some View {
        HStack(spacing: 26) {
            PlayerIconButton(
                systemName: "gobackward.10",
                accessibilityLabel: "Rewind 10 seconds",
                action: onSeekBackward
            )

            PlayPauseButton(isPaused: isPaused, action: onPlayPause)

            PlayerIconButton(
                systemName: "goforward.10",
                accessibilityLabel: "Skip forward 10 seconds",
                action: onSeekForward
            )
        }
        .padding(.bottom, 4)
    }
}

private struct PlayerControlsBackground: View {
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(
                colors: [
                    .black.opacity(0.55),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 180)

            Spacer()

            LinearGradient(
                colors: [
                    .clear,
                    .black.opacity(0.7)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
            .frame(height: 260)
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }
}

struct PlayerBadge: View {
    var title: String
    var systemImage: String?

    init(_ title: String, systemImage: String? = nil) {
        self.title = title
        self.systemImage = systemImage
    }

    var body: some View {
        HStack(spacing: 6) {
            if let systemImage {
                Image(systemName: systemImage)
            }
            Text(title)
                .font(.footnote.weight(.semibold))
        }
        .foregroundStyle(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            LinearGradient(
                colors: [
                    .white.opacity(0.24),
                    .white.opacity(0.08)
                ],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
            ),
            in: Capsule()
        )
        .overlay(
            Capsule()
                .stroke(Color.white.opacity(0.25), lineWidth: 1)
        )
    }
}
