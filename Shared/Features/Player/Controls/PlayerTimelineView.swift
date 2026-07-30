import SwiftUI

#if os(iOS)
    import UIKit
#elseif os(macOS)
    import AppKit
#endif

struct PlayerTimelineView: View {
    @Binding var position: Double
    var duration: Double?
    var bufferedAhead: Double
    var playbackPosition: Double
    var playbackRate: Float
    var showsEndsAtTime: Bool
    var chapters: [PlexChapter]
    var showsChaptersOnTimeline: Bool
    var scrubPreview: PlayerScrubPreview?
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
            if isEditing,
               let scrubPreview,
               scrubPreview.image != nil
            {
                PlayerScrubPreviewRail(
                    preview: scrubPreview,
                    duration: sliderUpperBound,
                )
                .transition(.opacity)
            }

            if showsChaptersOnTimeline,
               isEditing,
               let chapter = chapter(at: position)
            {
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
                    bufferedEnd: bufferedEnd,
                    chapters: timelineChapters,
                    onEditingChanged: handleEditingChanged(_:),
                )
            #else
                ZStack {
                    PlayerSegmentedTimelineRail(
                        chapters: timelineChapters,
                        duration: duration,
                        position: position,
                        bufferedEnd: bufferedEnd,
                    )
                    .frame(maxHeight: 28)

                    PlayerTracklessSlider(
                        value: sliderBinding,
                        in: 0 ... sliderUpperBound,
                        onEditingChanged: handleEditingChanged(_:),
                    )
                    .shadow(color: .black.opacity(0.25), radius: 12, x: 0, y: 8)
                }
            #endif

            HStack {
                Text(elapsedText)
                Spacer()
                HStack(spacing: 12) {
                    Text(remainingText)
                    if showsEndsAtTime {
                        TimelineView(.periodic(from: .now, by: 30)) { context in
                            if let endsAtText = playerEndsAtText(
                                position: position,
                                duration: duration,
                                playbackRate: playbackRate,
                                now: context.date,
                            ) {
                                Text(endsAtText)
                            }
                        }
                    }
                }
                .fixedSize()
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

    private var timelineChapters: [PlexChapter] {
        showsChaptersOnTimeline ? chapters : []
    }

    private var remainingText: String {
        guard let duration else { return "--:--" }
        let remaining = max(duration - position, 0)
        return "-\(formatTime(remaining))"
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

func playerEndsAtText(
    position: Double,
    duration: Double?,
    playbackRate: Float,
    now: Date,
) -> String? {
    guard let duration,
          duration.isFinite,
          duration > 0,
          position.isFinite,
          position >= 0,
          playbackRate.isFinite,
          playbackRate > 0
    else {
        return nil
    }

    let remaining = max(duration - position, 0)
    let wallClockRemaining = remaining / Double(playbackRate)
    guard wallClockRemaining.isFinite else { return nil }

    let endDate = now.addingTimeInterval(wallClockRemaining)
    let time = endDate.formatted(date: .omitted, time: .shortened)
    return String(localized: "player.timeline.endsAt \(time)")
}

struct PlayerScrubPreviewRail: View {
    var preview: PlayerScrubPreview
    var duration: Double
    var horizontalInset: CGFloat = 14

    private var cardSize: CGSize {
        #if os(tvOS)
            CGSize(width: 256, height: 144)
        #elseif os(macOS)
            CGSize(width: 200, height: 112.5)
        #else
            CGSize(width: 180, height: 101.25)
        #endif
    }

    var body: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            let usableWidth = max(width - horizontalInset * 2, 0)
            let progress = duration > 0
                ? min(max(preview.position / duration, 0), 1)
                : 0
            let targetX = horizontalInset + usableWidth * CGFloat(progress)
            let halfCardWidth = cardSize.width / 2
            let cardX = min(
                max(targetX, halfCardWidth),
                max(halfCardWidth, width - halfCardWidth),
            )

            if let image = preview.image {
                PlayerScrubPreviewCard(
                    image: image,
                    position: preview.position,
                    size: cardSize,
                )
                .position(x: cardX, y: cardSize.height / 2)
            }
        }
        .frame(height: cardSize.height)
        .accessibilityElement(children: .combine)
    }
}

struct PlayerScrubPreviewCard: View {
    var image: CGImage
    var position: Double
    var size: CGSize

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)

            Image(decorative: image, scale: 1)
                .resizable()
                .scaledToFill()
                .id(ObjectIdentifier(image))
                .transition(.opacity)
        }
        .frame(width: size.width, height: size.height)
        .clipped()
        .overlay(alignment: .bottomTrailing) {
            Text(playerTimestampText(position))
                .font(.caption.monospacedDigit().weight(.semibold))
                .foregroundStyle(.white)
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(.black.opacity(0.72), in: Capsule())
                .padding(8)
        }
        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .stroke(.white.opacity(0.2), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.45), radius: 12, x: 0, y: 7)
        .animation(
            .easeOut(duration: 0.1),
            value: ObjectIdentifier(image),
        )
    }
}

#if os(iOS)
    private struct PlayerTracklessSlider: UIViewRepresentable {
        @Binding var value: Double
        var range: ClosedRange<Double>
        var onEditingChanged: (Bool) -> Void

        init(
            value: Binding<Double>,
            in range: ClosedRange<Double>,
            onEditingChanged: @escaping (Bool) -> Void,
        ) {
            _value = value
            self.range = range
            self.onEditingChanged = onEditingChanged
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeUIView(context: Context) -> UISlider {
            let slider = UISlider()
            slider.isContinuous = true
            slider.minimumTrackTintColor = .clear
            slider.maximumTrackTintColor = .clear
            slider.addTarget(
                context.coordinator,
                action: #selector(Coordinator.editingBegan(_:)),
                for: .touchDown,
            )
            slider.addTarget(
                context.coordinator,
                action: #selector(Coordinator.valueChanged(_:)),
                for: .valueChanged,
            )
            slider.addTarget(
                context.coordinator,
                action: #selector(Coordinator.editingEnded(_:)),
                for: [.touchUpInside, .touchUpOutside, .touchCancel],
            )
            return slider
        }

        func updateUIView(_ slider: UISlider, context: Context) {
            context.coordinator.parent = self
            slider.minimumValue = Float(range.lowerBound)
            slider.maximumValue = Float(range.upperBound)
            slider.minimumTrackTintColor = .clear
            slider.maximumTrackTintColor = .clear

            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            if abs(Double(slider.value) - clampedValue) > 0.001 {
                slider.setValue(Float(clampedValue), animated: false)
            }
        }

        final class Coordinator: NSObject {
            var parent: PlayerTracklessSlider
            private var isEditing = false

            init(parent: PlayerTracklessSlider) {
                self.parent = parent
            }

            @objc func editingBegan(_: UISlider) {
                beginEditingIfNeeded()
            }

            @objc func valueChanged(_ slider: UISlider) {
                let commitsImmediately = !slider.isTracking && !isEditing
                if commitsImmediately {
                    beginEditingIfNeeded()
                }

                parent.value = Double(slider.value)

                if commitsImmediately {
                    endEditingIfNeeded()
                }
            }

            @objc func editingEnded(_ slider: UISlider) {
                parent.value = Double(slider.value)
                endEditingIfNeeded()
            }

            private func beginEditingIfNeeded() {
                guard !isEditing else { return }
                isEditing = true
                parent.onEditingChanged(true)
            }

            private func endEditingIfNeeded() {
                guard isEditing else { return }
                isEditing = false
                parent.onEditingChanged(false)
            }
        }
    }
#elseif os(macOS)
    struct PlayerTracklessSlider: NSViewRepresentable {
        @Binding var value: Double
        var range: ClosedRange<Double>
        var onEditingChanged: (Bool) -> Void

        init(
            value: Binding<Double>,
            in range: ClosedRange<Double>,
            onEditingChanged: @escaping (Bool) -> Void,
        ) {
            _value = value
            self.range = range
            self.onEditingChanged = onEditingChanged
        }

        func makeCoordinator() -> Coordinator {
            Coordinator(parent: self)
        }

        func makeNSView(context: Context) -> TracklessNSSlider {
            let slider = TracklessNSSlider()
            slider.cell = TracklessNSSliderCell()
            slider.isContinuous = true
            slider.target = context.coordinator
            slider.action = #selector(Coordinator.valueChanged(_:))
            slider.onEditingChanged = context.coordinator.handleEditingChanged(_:)
            return slider
        }

        func updateNSView(_ slider: TracklessNSSlider, context: Context) {
            context.coordinator.parent = self
            slider.minValue = range.lowerBound
            slider.maxValue = range.upperBound
            slider.onEditingChanged = context.coordinator.handleEditingChanged(_:)

            let clampedValue = min(max(value, range.lowerBound), range.upperBound)
            if abs(slider.doubleValue - clampedValue) > 0.001 {
                slider.doubleValue = clampedValue
            }
        }

        final class Coordinator: NSObject {
            var parent: PlayerTracklessSlider

            init(parent: PlayerTracklessSlider) {
                self.parent = parent
            }

            @objc func valueChanged(_ slider: TracklessNSSlider) {
                let commitsImmediately = !slider.isInteracting
                if commitsImmediately {
                    parent.onEditingChanged(true)
                }

                parent.value = slider.doubleValue

                if commitsImmediately {
                    parent.onEditingChanged(false)
                }
            }

            func handleEditingChanged(_ editing: Bool) {
                parent.onEditingChanged(editing)
            }
        }
    }

    final class TracklessNSSlider: NSSlider {
        var onEditingChanged: ((Bool) -> Void)?
        private(set) var isInteracting = false

        override func mouseDown(with event: NSEvent) {
            isInteracting = true
            onEditingChanged?(true)
            super.mouseDown(with: event)
            isInteracting = false
            onEditingChanged?(false)
        }
    }

    final class TracklessNSSliderCell: NSSliderCell {
        override func drawBar(inside _: NSRect, flipped _: Bool) {}
    }
#endif
