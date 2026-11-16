import SwiftUI

struct PlayerTimelineScrubberView: View {
    @Binding var position: Double
    var upperBound: Double
    var duration: Double?
    var bufferedEnd: Double
    var chapters: [MediaChapter]
    var skipSegments: [SkipSegment]
    var onEditingChanged: (Bool) -> Void
    var onCancel: () -> Void
    var swipesScrub: Bool
    var onIdleSwipe: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @FocusState private var isFocused: Bool

    private let horizontalInset: CGFloat = 14
    private let thumbDiameter: CGFloat = 28

    private var playbackProgress: Double {
        guard upperBound > 0 else { return 0 }
        return min(max(position / upperBound, 0), 1)
    }

    private var scrubStep: Double {
        guard let duration else { return 10 }
        return min(max(duration / 300, 5), 60)
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usableWidth = max(width - horizontalInset * 2, 0)
            let thumbX = horizontalInset + usableWidth * playbackProgress

            ZStack(alignment: .leading) {
                PlayerSegmentedTimelineRail(
                    chapters: chapters,
                    skipSegments: skipSegments,
                    duration: duration,
                    position: position,
                    bufferedEnd: bufferedEnd,
                    horizontalInset: horizontalInset,
                    trackHeight: 8,
                    preferredGap: 6,
                )

                Circle()
                    .fill(Color.white)
                    .frame(width: thumbDiameter, height: thumbDiameter)
                    .scaleEffect(isFocused ? 1.0 : 0.75)
                    .shadow(color: .black.opacity(0.45), radius: 10, x: 0, y: 6)
                    .offset(x: thumbX - thumbDiameter / 2)
                    .animation(Motion.animation(Motion.focusScale, reduceMotion: reduceMotion), value: isFocused)
            }
            .animation(Motion.focus, value: isFocused)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: 32)
        .playerScrubInteraction(
            position: $position,
            upperBound: upperBound,
            stepSize: scrubStep,
            isFocused: isFocused,
            swipesScrub: swipesScrub,
            onEditingChanged: onEditingChanged,
            onCancel: onCancel,
            onIdleSwipe: onIdleSwipe,
        )
        .focused($isFocused)
        .accessibilityHidden(true)
    }
}
