import Foundation
import Observation

/// Shows the media details after playback stays paused, untouched, for a while.
@MainActor
@Observable
final class PauseScreenPresentation {
    private(set) var isPresented = false

    @ObservationIgnored private let delay: Duration
    @ObservationIgnored private var isEligible = false
    @ObservationIgnored private var task: Task<Void, Never>?

    init(delay: Duration = .seconds(10)) {
        self.delay = delay
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
        task = Task { [weak self, delay] in
            do {
                try await Task.sleep(for: delay)
            } catch {
                return
            }
            guard let self, !Task.isCancelled, isEligible else { return }
            isPresented = true
            task = nil
        }
    }
}
