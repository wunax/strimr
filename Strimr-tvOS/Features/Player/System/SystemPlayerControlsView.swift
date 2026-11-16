import SwiftUI

/// Player controls styled after the tvOS system player: a thin timeline at the bottom, the title above it, round
/// glass buttons on the right and tabs below.
struct SystemPlayerControlsView: View {
    var state: PlayerControlsState
    var actions: PlayerControlsActions
    @Binding var position: Double

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var focus: SystemPlayerFocus?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            topRow

            Spacer(minLength: 0)

            if !state.isScrubbing {
                titleRow
                    .padding(.bottom, 22)
                    .transition(.opacity)
            }

            timeline
        }
        .padding(.horizontal, SystemPlayerMetrics.horizontalMargin)
        .padding(.top, SystemPlayerMetrics.topMargin)
        .padding(.bottom, SystemPlayerMetrics.bottomMargin)
        .background(alignment: .bottom) {
            SystemPlayerControlsBackground()
        }
        .ignoresSafeArea()
        .animation(Motion.animation(Motion.controls, reduceMotion: reduceMotion), value: state.isScrubbing)
        .onAppear {
            DispatchQueue.main.async {
                focus = .timeline
            }
        }
        .onMoveCommand { _ in
            actions.userInteraction()
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
                if !eyebrowParts.isEmpty {
                    Text(eyebrowParts.joined(separator: " · "))
                        .font(.bodyText.weight(.medium))
                        .foregroundStyle(.textPrimary)
                        .lineLimit(1)
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
        }
    }

    @ViewBuilder
    private var timeline: some View {
        if let live = state.live {
            LiveTVPlayerStatusRow(
                behindLiveSeconds: live.behindLiveSeconds,
                isAtLiveEdge: live.isAtLiveEdge,
                onGoLive: actions.goLive,
            )
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
            )
            .focused($focus, equals: .timeline)
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
    case button(String)
    case tab(PlayerInfoTab)
    case contextualAction
}

enum SystemPlayerMetrics {
    static let horizontalMargin: CGFloat = 80
    static let topMargin: CGFloat = 50
    static let bottomMargin: CGFloat = 48
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
