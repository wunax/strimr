import SwiftUI

struct PlayerTimelineView: View {
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var playbackPosition: Double
    var chapters: [PlexChapter]
    var onEditingChanged: (Bool) -> Void
    @State private var isEditing = false

    private var sliderUpperBound: Double {
        max(duration ?? 0, position, playbackPosition, 1)
    }

    private var bufferedEnd: Double {
        let bufferedPosition = playbackPosition + bufferedAhead
        guard let duration else { return bufferedPosition }
        return min(bufferedPosition, duration)
    }

    private var bufferedProgress: Double {
        guard sliderUpperBound > 0 else { return 0 }
        return min(max(bufferedEnd / sliderUpperBound, 0), 1)
    }

    private var sliderBinding: Binding<Double> {
        Binding(
            get: {
                min(position, sliderUpperBound)
            },
            set: { newValue in
                position = newValue
            },
        )
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if isEditing, let chapter = chapter(at: position) {
                Text(chapter.displayTitle)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white.opacity(0.9))
                    .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
                    .transition(.opacity)
            }

            #if os(tvOS)
                PlayerTimelineScrubberTVView(
                    position: $position,
                    upperBound: sliderUpperBound,
                    duration: duration,
                    bufferedProgress: bufferedProgress,
                    chapters: chapters,
                    onEditingChanged: handleEditingChanged(_:),
                )
            #else
                ZStack {
                    bufferTrack
                    PlayerChapterTicksView(
                        chapters: chapters,
                        duration: duration,
                    )
                    .frame(maxHeight: 28)
                    Slider(
                        value: sliderBinding,
                        in: 0 ... sliderUpperBound,
                        onEditingChanged: handleEditingChanged(_:),
                    )
                        .tint(.white)
                        .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
                }
            #endif

            HStack {
                Text(elapsedText)
                Spacer()
                Text(remainingText)
            }
            .font(.footnote.monospacedDigit())
            .foregroundStyle(.white.opacity(0.9))
            .shadow(color: .black.opacity(0.3), radius: 4, x: 0, y: 2)
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 8)
    }

    private var elapsedText: String {
        formatTime(position)
    }

    private var remainingText: String {
        guard let duration else { return "--:--" }
        let remaining = max(duration - position, 0)
        return "-\(formatTime(remaining))"
    }

    private var bufferTrack: some View {
        GeometryReader { proxy in
            let bufferWidth = proxy.size.width * bufferedProgress
            ZStack(alignment: .leading) {
                Capsule()
                    .fill(Color.white.opacity(0.35))
                Capsule()
                    .fill(Color.white.opacity(0.65))
                    .frame(width: bufferWidth)
            }
            .frame(height: 4)
            .frame(maxHeight: .infinity, alignment: .center)
            .allowsHitTesting(false)
        }
        .frame(maxWidth: .infinity, maxHeight: 28)
        .accessibilityHidden(true)
    }

    private func formatTime(_ seconds: Double) -> String {
        let totalSeconds = max(Int(seconds.rounded()), 0)
        let hours = totalSeconds / 3600
        let minutes = (totalSeconds % 3600) / 60
        let secs = totalSeconds % 60

        if hours > 0 {
            return String(format: "%d:%02d:%02d", hours, minutes, secs)
        } else {
            return String(format: "%02d:%02d", minutes, secs)
        }
    }

    private func chapter(at time: Double) -> PlexChapter? {
        chapters.first { $0.contains(time: time) }
    }

    private func handleEditingChanged(_ editing: Bool) {
        withAnimation(.easeInOut(duration: 0.15)) {
            isEditing = editing
        }
        onEditingChanged(editing)
    }
}
