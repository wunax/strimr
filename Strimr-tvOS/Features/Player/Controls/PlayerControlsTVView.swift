import SwiftUI

struct PlayerControlsTVView: View {
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
    var onUserInteraction: () -> Void
    var isWatchTogether: Bool
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

        if supportsHDR {
            badges.append(
                PlayerControlBadge(
                    id: "hdr",
                    title: String(localized: "player.badge.hdr"),
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
            }

            Spacer()

            if !isScrubbing {
                PlayerAuxiliaryControlsTVRow(
                    skipMarkerTitle: skipMarkerTitle,
                    onSkipMarker: onSkipMarker,
                    badges: playbackBadges,
                )
                .padding(.horizontal, 24)
            }

            PlayerTimelineView(
                position: $position,
                duration: duration,
                bufferedAhead: bufferedAhead,
                playbackPosition: bufferBasePosition,
                onEditingChanged: onScrubbingChanged,
            )

            ZStack {
                HStack(spacing: 36) {
                    PlayerSettingButton(
                        systemImage: "speedometer",
                        action: onShowSpeedSettings,
                    )

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

                HStack(spacing: 30) {
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
                }
            }
        }
        .padding(.horizontal, 40)
        .padding(.vertical, 28)
        .background {
            PlayerControlsTVBackground()
        }
        .onAppear {
            focusedControl = .playPause
        }
        .onMoveCommand { _ in
            onUserInteraction()
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

private struct PlayerAuxiliaryControlsTVRow: View {
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
}

private struct PlayerControlsTVBackground: View {
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
