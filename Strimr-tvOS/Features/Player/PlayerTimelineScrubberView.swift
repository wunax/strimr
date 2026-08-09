import SwiftUI

struct PlayerTimelineScrubberView: View {
    @Binding var position: Double
    var upperBound: Double
    var duration: Double?
    var bufferedEnd: Double
    var chapters: [PlexChapter]
    var onEditingChanged: (Bool) -> Void

    @State private var consecutiveMoves = 0
    @State private var isScrubbing = false
    @State private var commitWorkItem: DispatchWorkItem?
    @FocusState private var isFocused: Bool

    private let scrubCommitDelay: TimeInterval = 0.4
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
                    .animation(.easeInOut(duration: 0.15), value: isFocused)
            }
            .animation(.easeInOut(duration: 0.15), value: isFocused)
        }
        .contentShape(Rectangle())
        .frame(maxWidth: .infinity, maxHeight: 32)
        .focusable()
        .focused($isFocused)
        .onMoveCommand { direction in
            guard isFocused else { return }

            startScrubbingIfNeeded()
            consecutiveMoves += 1
            let multiplier = min(Double(consecutiveMoves), 5)
            let delta = scrubStep * multiplier

            switch direction {
            case .left:
                position = max(0, position - delta)
            case .right:
                position = min(upperBound, position + delta)
            default:
                break
            }

            scheduleCommit()
        }
        .onChange(of: isFocused) { _, focused in
            if !focused {
                finishScrubbingIfNeeded()
            }
        }
        .onDisappear {
            commitWorkItem?.cancel()
        }
        .accessibilityHidden(true)
    }

    private func startScrubbingIfNeeded() {
        guard !isScrubbing else { return }
        isScrubbing = true
        onEditingChanged(true)
    }

    private func scheduleCommit() {
        commitWorkItem?.cancel()
        let workItem = DispatchWorkItem {
            isScrubbing = false
            consecutiveMoves = 0
            onEditingChanged(false)
        }
        commitWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + scrubCommitDelay, execute: workItem)
    }

    private func finishScrubbingIfNeeded() {
        consecutiveMoves = 0
        commitWorkItem?.cancel()
        commitWorkItem = nil

        guard isScrubbing else { return }
        isScrubbing = false
        onEditingChanged(false)
    }
}
