import SwiftUI

struct PlayerControlsVisionView: View {
    var media: MediaItem?
    var isPaused: Bool
    var videoResolution: String?
    var supportsHDR: Bool
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var bufferBasePosition: Double
    var isScrubbing: Bool
    var onShowAudioSettings: () -> Void
    var onShowSubtitleSettings: () -> Void
    var onShowSpeedSettings: () -> Void
    var onSeekBackward: () -> Void
    var onPlayPause: () -> Void
    var onSeekForward: () -> Void
    var seekBackwardSeconds: Int
    var seekForwardSeconds: Int
    var onScrubbingChanged: (Bool) -> Void
    var skipMarkerTitle: String?
    var onSkipMarker: (() -> Void)?
    var isWatchTogether: Bool
    var onClose: () -> Void

    var body: some View {
        VStack(spacing: 14) {
            titleRow

            PlayerTimelineView(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: bufferBasePosition,
                onEditingChanged: onScrubbingChanged,
            )

            controlsRow
        }
        .padding(.horizontal, 28)
        .padding(.vertical, 20)
    }

    private var titleRow: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                if let title = media?.primaryLabel {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                        .lineLimit(1)
                }

                if let subtitle = media?.tertiaryLabel {
                    Text(subtitle)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            HStack(spacing: 8) {
                if isWatchTogether {
                    Text("watchTogether.badge")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(
                            Capsule(style: .continuous)
                                .fill(Color.secondary.opacity(0.15)),
                        )
                }

                if let videoResolution {
                    PlayerBadge(videoResolution, systemImage: nil)
                }

                if supportsHDR {
                    PlayerBadge(
                        String(localized: "player.badge.hdr"),
                        systemImage: "sparkles",
                    )
                }
            }
        }
    }

    private var controlsRow: some View {
        ZStack {
            HStack(spacing: 16) {
                Button(action: onShowSpeedSettings) {
                    Image(systemName: "speedometer")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Button(action: onShowAudioSettings) {
                    Image(systemName: "speaker.wave.2")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                Button(action: onShowSubtitleSettings) {
                    Image(systemName: "captions.bubble")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)

                if let skipMarkerTitle, let onSkipMarker {
                    Button(action: onSkipMarker) {
                        Text(skipMarkerTitle)
                            .font(.subheadline.weight(.semibold))
                    }
                    .buttonStyle(.bordered)
                    .tint(.brandSecondary)
                }

                Spacer()
            }

            HStack(spacing: 24) {
                Button(action: onSeekBackward) {
                    Image(systemName: iconName(prefix: "gobackward", seconds: seekBackwardSeconds))
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "player.controls.rewindSeconds \(seekBackwardSeconds)"))

                Button(action: onPlayPause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                        .font(.title2.weight(.semibold))
                        .frame(width: 44, height: 44)
                }
                .buttonStyle(.bordered)
                .tint(.white)

                Button(action: onSeekForward) {
                    Image(systemName: iconName(prefix: "goforward", seconds: seekForwardSeconds))
                        .font(.title3.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(String(localized: "player.controls.skipForwardSeconds \(seekForwardSeconds)"))
            }

            HStack {
                Spacer()

                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(.body.weight(.semibold))
                }
                .buttonStyle(.borderless)
                .accessibilityLabel(Text("common.actions.close"))
            }
        }
    }

    private func iconName(prefix: String, seconds: Int) -> String {
        let supported = [5, 10, 15, 30, 45, 60]
        guard supported.contains(seconds) else { return prefix }
        return "\(prefix).\(seconds)"
    }
}
