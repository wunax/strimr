import Foundation

/// Skips markers automatically once a countdown elapses. The countdown runs on played time, so it waits while
/// playback is paused, and any seek cancels it until playback leaves that marker.
struct AutomaticMarkerSkip {
    struct Countdown: Equatable {
        let marker: SkipSegment
        let startPosition: TimeInterval
        let duration: TimeInterval
        fileprivate(set) var position: TimeInterval

        var progress: Double {
            guard duration > 0 else { return 1 }
            return min(max((position - startPosition) / duration, 0), 1)
        }

        var remainingSeconds: Int {
            Int(max(duration - (position - startPosition), 0).rounded(.up))
        }

        fileprivate var isFinished: Bool {
            position - startPosition >= duration
        }
    }

    /// Position steps a playing clock reports between updates; anything outside is a seek.
    static let playbackStep: ClosedRange<TimeInterval> = -0.25 ... 2.5

    private(set) var countdown: Countdown?
    /// Skipped or cancelled, so it is left alone until playback leaves it.
    private var handledMarker: SkipSegment?

    /// Returns the marker to skip now, if any.
    mutating func update(
        position: TimeInterval,
        markers: [SkipSegment],
        enabledKinds: Set<SkipSegment.Kind>,
        countdownSeconds: Int,
    ) -> SkipSegment? {
        if let handledMarker {
            guard !handledMarker.contains(time: position) else { return nil }
            self.handledMarker = nil
        }

        if let current = countdown {
            if !current.marker.contains(time: position) {
                // The marker ended or playback seeked away; the countdown never completed, so nothing is skipped.
                countdown = nil
            } else if !Self.playbackStep.contains(position - current.position)
                || !enabledKinds.contains(current.marker.kind)
            {
                cancel()
                return nil
            } else {
                countdown?.position = position
                return finishIfElapsed()
            }
        }

        guard let marker = markers.first(where: { enabledKinds.contains($0.kind) && $0.contains(time: position) })
        else { return nil }

        countdown = Countdown(
            marker: marker,
            startPosition: position,
            duration: TimeInterval(max(countdownSeconds, 0)),
            position: position,
        )
        return finishIfElapsed()
    }

    /// Stops the running countdown without skipping, and keeps it from restarting within the same marker.
    mutating func cancel() {
        guard let countdown else { return }
        handledMarker = countdown.marker
        self.countdown = nil
    }

    mutating func reset() {
        countdown = nil
        handledMarker = nil
    }

    private mutating func finishIfElapsed() -> SkipSegment? {
        guard let countdown, countdown.isFinished else { return nil }
        handledMarker = countdown.marker
        self.countdown = nil
        return countdown.marker
    }
}
