import SwiftUI

/// Thin timeline of the system style: the elapsed time follows the playhead, and a scrub shows its target above it
/// with a mark at the position it started from.
struct SystemPlayerTimelineView: View {
    @Binding var position: Double
    var state: PlayerControlsState
    var isFocused: Bool
    var onEditingChanged: (Bool) -> Void
    var onCancel: () -> Void
    var onSeekBackward: () -> Void
    var onSeekForward: () -> Void
    var onPlayPause: () -> Void
    var onIdleSwipe: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var scrubOrigin: Double?
    /// Direction of the last left or right jump during playback, shown beside the elapsed time as in the system player.
    @State private var jumpDirection: MoveCommandDirection?
    @State private var jumpIndicatorHide: DispatchWorkItem?
    @State private var elapsedContentWidth: CGFloat = 0
    @State private var remainingTextWidth: CGFloat = 0
    @State private var endsAtWidth: CGFloat = 0

    private let barAreaHeight: CGFloat = 24
    private let labelsHeight: CGFloat = 34
    private let remainingLabelsSpacing: CGFloat = 6
    private let previewHeight: CGFloat = 200
    private let previewGap: CGFloat = 18

    private var upperBound: Double {
        max(state.duration ?? 0, position, state.bufferBasePosition, 1)
    }

    private var bufferedEnd: Double {
        let end = state.bufferBasePosition + state.bufferedAhead
        return state.duration.map { min(end, $0) } ?? end
    }

    /// Same pace as the classic timeline: about 300 presses across the video.
    private var stepSize: Double {
        guard let duration = state.duration else { return 10 }
        return min(max(duration / 300, 5), 60)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let playheadX = x(for: position, width: width)

            VStack(spacing: 0) {
                ZStack(alignment: .leading) {
                    PlayerSegmentedTimelineRail(
                        chapters: state.showsChaptersOnTimeline ? state.chapters : [],
                        skipSegments: state.skipSegments,
                        duration: state.duration,
                        position: position,
                        bufferedEnd: bufferedEnd,
                        horizontalInset: 0,
                        trackHeight: 12,
                        preferredGap: 4,
                    )
                    // The system bar keeps its size when focus leaves it and only fades.
                    .opacity(isFocused ? 1 : 0.55)

                    if let scrubOrigin {
                        Capsule()
                            .fill(.textSecondary)
                            .frame(width: 3, height: 22)
                            .offset(x: x(for: scrubOrigin, width: width) - 1.5)
                    }

                    Capsule()
                        .fill(.progressFill)
                        .frame(width: 4, height: 26)
                        .shadow(color: .black.opacity(0.35), radius: 4)
                        .offset(x: playheadX - 2)
                }
                .frame(height: barAreaHeight)
                .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)

                timeLabels(width: width, playheadX: playheadX)
            }
            .overlay(alignment: .topLeading) {
                if scrubOrigin != nil, let preview = state.scrubPreview, let image = preview.image {
                    let size = previewSize(for: image)
                    SystemPlayerScrubThumbnail(image: image, size: size)
                        .offset(
                            x: clamped(playheadX - size.width / 2, width: size.width, in: width),
                            y: -size.height - previewGap,
                        )
                        .transition(.opacity)
                }
            }
        }
        .frame(height: barAreaHeight + labelsHeight)
        .contentShape(Rectangle())
        .playerScrubInteraction(
            position: $position,
            upperBound: upperBound,
            stepSize: stepSize,
            isFocused: isFocused,
            pressesScrub: state.isPaused,
            swipesScrub: state.isPaused,
            onEditingChanged: handleEditingChanged(_:),
            onCancel: handleCancel,
            onIdleMove: handleJump(_:),
            onIdleSelect: onPlayPause,
            // Like the system player, confirming a scrub made while paused resumes playback.
            onClickCommit: {
                if state.isPaused {
                    onPlayPause()
                }
            },
            onIdleSwipe: onIdleSwipe,
        )
        .accessibilityElement()
        .accessibilityLabel(Text("player.timeline.accessibilityLabel"))
        .accessibilityValue(Text(verbatim: "\(elapsedText), \(remainingText)"))
        .accessibilityAdjustableAction { direction in
            switch direction {
            case .increment: onSeekForward()
            case .decrement: onSeekBackward()
            @unknown default: break
            }
        }
    }

    private func timeLabels(width: CGFloat, playheadX: CGFloat) -> some View {
        let elapsedWidth: CGFloat = state.isPaused || jumpDirection != nil ? 150 : 110
        let elapsedX = clamped(playheadX - elapsedWidth / 2, width: elapsedWidth, in: width)
        // As in the system player, the labels on the right step aside when the elapsed time reaches them near the
        // end: the end time first, then the remaining time.
        let elapsedReach = elapsedX + (elapsedWidth + elapsedContentWidth) / 2 + 24
        let remainingStart = width - remainingTextWidth
        let isEndsAtHidden = elapsedReach > remainingStart - endsAtWidth - remainingLabelsSpacing
        let isRemainingHidden = elapsedReach > remainingStart
        return ZStack(alignment: .topLeading) {
            HStack(spacing: 8) {
                if jumpDirection == .left {
                    jumpIndicator(.left)
                }
                Text(elapsedText)
                if state.isPaused {
                    Image(systemName: "pause.circle")
                        .accessibilityHidden(true)
                } else if jumpDirection == .right {
                    jumpIndicator(.right)
                }
            }
            .fixedSize()
            .onGeometryChange(for: CGFloat.self, of: \.size.width) { elapsedContentWidth = $0 }
            .frame(width: elapsedWidth)
            .offset(x: elapsedX)

            HStack(spacing: remainingLabelsSpacing) {
                Text(remainingText)
                    .fixedSize()
                    .onGeometryChange(for: CGFloat.self, of: \.size.width) { remainingTextWidth = $0 }
                    .opacity(isRemainingHidden ? 0 : 1)
                if state.showsEndsAtTime, scrubOrigin == nil, !isEndsAtHidden {
                    TimelineView(.periodic(from: .now, by: 30)) { context in
                        if let endsAt = playerEndsAtText(
                            position: position,
                            duration: state.duration,
                            playbackRate: state.playbackRate,
                            now: context.date,
                        ) {
                            Text(verbatim: "· \(endsAt)")
                                .foregroundStyle(.textSecondary)
                                .fixedSize()
                                .onGeometryChange(for: CGFloat.self, of: \.size.width) { endsAtWidth = $0 }
                        }
                    }
                    .transition(.opacity)
                }
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
            .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: isEndsAtHidden)
            .animation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion), value: isRemainingHidden)
        }
        .font(.facts.weight(.semibold).monospacedDigit())
        .foregroundStyle(isFocused ? .textPrimary : .textSecondary)
        .videoTextShadow()
        .frame(height: labelsHeight)
        .padding(.top, 6)
    }

    private func jumpIndicator(_ direction: MoveCommandDirection) -> some View {
        Image(systemName: direction == .left ? state.seekBackwardSymbol : state.seekForwardSymbol)
            .transition(.opacity)
            .accessibilityHidden(true)
    }

    private func handleJump(_ direction: MoveCommandDirection) {
        direction == .left ? onSeekBackward() : onSeekForward()
        jumpIndicatorHide?.cancel()
        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
            jumpDirection = direction
        }
        let hide = DispatchWorkItem {
            withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
                jumpDirection = nil
            }
        }
        jumpIndicatorHide = hide
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.2, execute: hide)
    }

    private var elapsedText: String {
        playerTimestampText(position)
    }

    private var remainingText: String {
        guard let duration = state.duration else { return "--:--" }
        return "-\(playerTimestampText(max(duration - position, 0)))"
    }

    private func x(for time: Double, width: CGFloat) -> CGFloat {
        width * CGFloat(min(max(time / upperBound, 0), 1))
    }

    /// Keeps something `itemWidth` wide, centered on a point of the timeline, inside the timeline.
    private func clamped(_ x: CGFloat, width itemWidth: CGFloat, in width: CGFloat) -> CGFloat {
        min(max(x, 0), max(width - itemWidth, 0))
    }

    private func previewSize(for image: CGImage) -> CGSize {
        let aspect = image.height > 0 ? CGFloat(image.width) / CGFloat(image.height) : 16 / 9
        let width = min(previewHeight * aspect, 420)
        return CGSize(width: width, height: width / aspect)
    }

    private func handleEditingChanged(_ editing: Bool) {
        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
            scrubOrigin = editing ? position : nil
        }
        onEditingChanged(editing)
    }

    private func handleCancel() {
        withAnimation(Motion.animation(Motion.crossfade, reduceMotion: reduceMotion)) {
            scrubOrigin = nil
        }
        onCancel()
    }
}

private struct SystemPlayerScrubThumbnail: View {
    var image: CGImage
    var size: CGSize

    var body: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .scaledToFill()
            .frame(width: size.width, height: size.height)
            .clipShape(RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous))
            .overlay {
                RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous)
                    .stroke(.strokeSubtle, lineWidth: 1)
            }
            .shadow(color: .black.opacity(0.45), radius: 12, y: 6)
            .animation(Motion.crossfade, value: ObjectIdentifier(image))
    }
}
