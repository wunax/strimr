import Foundation
import Observation

enum DoubleTapSeekZone: Equatable {
    case backward
    case center
    case forward

    init(x: Double, width: Double) {
        guard width > 0 else {
            self = .center
            return
        }
        switch x / width {
        case ..<(1.0 / 3.0): self = .backward
        case (2.0 / 3.0)...: self = .forward
        default: self = .center
        }
    }
}

/// Turns double taps on the sides of the player into seeks. Further single taps on the same side keep adding
/// to the pending seek, which is applied once tapping stops so a transcode restarts only once.
@MainActor
@Observable
final class DoubleTapSeek {
    struct Pending: Equatable {
        let forward: Bool
        var steps: Int
    }

    private(set) var pending: Pending?

    @ObservationIgnored var onCommit: ((Pending) -> Void)?
    @ObservationIgnored private let doubleTapWindow: Duration
    @ObservationIgnored private let commitDelay: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var lastTap: (zone: DoubleTapSeekZone, instant: ContinuousClock.Instant)?
    @ObservationIgnored private var commitTask: Task<Void, Never>?

    init(
        doubleTapWindow: Duration = .milliseconds(300),
        commitDelay: Duration = .milliseconds(700),
        clock: any Clock<Duration> = ContinuousClock(),
    ) {
        self.doubleTapWindow = doubleTapWindow
        self.commitDelay = commitDelay
        self.clock = clock
    }

    /// Returns whether the tap was consumed by a seek, in which case the caller skips its single-tap action.
    func registerTap(in zone: DoubleTapSeekZone, at instant: ContinuousClock.Instant = .now) -> Bool {
        let forward: Bool
        switch zone {
        case .center:
            commit()
            lastTap = nil
            return false
        case .backward: forward = false
        case .forward: forward = true
        }

        if let pending {
            if pending.forward == forward {
                self.pending?.steps += 1
                scheduleCommit()
            } else {
                commit()
                start(forward: forward)
            }
            return true
        }

        if let lastTap, lastTap.zone == zone, instant - lastTap.instant <= doubleTapWindow {
            self.lastTap = nil
            start(forward: forward)
            return true
        }

        lastTap = (zone, instant)
        return false
    }

    func commit() {
        commitTask?.cancel()
        commitTask = nil
        guard let pending else { return }
        self.pending = nil
        onCommit?(pending)
    }

    func cancel() {
        commitTask?.cancel()
        commitTask = nil
        pending = nil
        lastTap = nil
    }

    private func start(forward: Bool) {
        pending = Pending(forward: forward, steps: 1)
        scheduleCommit()
    }

    private func scheduleCommit() {
        commitTask?.cancel()
        commitTask = Task { [weak self, commitDelay, clock] in
            do {
                try await clock.sleep(for: commitDelay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled else { return }
            commit()
        }
    }
}
