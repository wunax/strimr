import Foundation
import Observation

/// Shows the media details after playback stays paused, untouched, for a while.
@MainActor
@Observable
final class PauseScreenPresentation {
    private(set) var isPresented = false

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private let clock: any Clock<Duration>
    @ObservationIgnored private var isEligible = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(delay: Duration = .seconds(10), clock: any Clock<Duration> = ContinuousClock()) {
        self.delay = delay
        self.clock = clock
    }

    func update(isEligible: Bool) {
        guard isEligible != self.isEligible else { return }
        self.isEligible = isEligible
        if isEligible {
            restartCountdown()
        } else {
            cancel()
        }
    }

    /// Returns whether the pause screen was visible, so the caller can swallow the input that dismissed it.
    @discardableResult
    func registerInteraction() -> Bool {
        let wasPresented = isPresented
        isPresented = false
        if isEligible {
            restartCountdown()
        }
        return wasPresented
    }

    func cancel() {
        task?.cancel()
        task = nil
        isPresented = false
    }

    private func restartCountdown() {
        task?.cancel()
        task = Task { [weak self, delay, clock] in
            do {
                try await clock.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, isEligible else { return }
            isPresented = true
            task = nil
        }
    }
}
