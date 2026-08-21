import Foundation
import Observation

@MainActor
@Observable
final class NextEpisodePresentation {
    private(set) var nextViewModel: PlayerViewModel?
    private(set) var remainingSeconds: Int?
    private(set) var generation = 0

    @ObservationIgnored private var countdownTask: Task<Void, Never>?

    var nextMedia: MediaItem? {
        nextViewModel?.media
    }

    var isPresented: Bool {
        nextViewModel != nil
    }

    func present(next: PlayerViewModel, mode: NextEpisodeAutoplay) {
        reset()
        nextViewModel = next
        remainingSeconds = mode.delaySeconds.flatMap { $0 > 0 ? $0 : nil }
        generation &+= 1
    }

    func startCountdown(onComplete: @escaping (PlayerViewModel) async -> Void) {
        guard remainingSeconds != nil, countdownTask == nil else { return }

        countdownTask = Task { [weak self] in
            guard let self else { return }

            while let remaining = remainingSeconds, remaining > 0 {
                do {
                    try await Task.sleep(for: .seconds(1))
                } catch {
                    return
                }

                guard !Task.isCancelled else { return }
                remainingSeconds = remaining - 1
            }

            guard !Task.isCancelled, let next = takeNext() else { return }
            await onComplete(next)
        }
    }

    func playNow() -> PlayerViewModel? {
        countdownTask?.cancel()
        countdownTask = nil
        return takeNext()
    }

    func cancel() {
        countdownTask?.cancel()
        countdownTask = nil
        _ = takeNext()
    }

    func cancelCountdown() {
        countdownTask?.cancel()
        countdownTask = nil
    }

    func reset() {
        cancelCountdown()
        _ = takeNext()
    }

    private func takeNext() -> PlayerViewModel? {
        let next = nextViewModel
        countdownTask = nil
        nextViewModel = nil
        remainingSeconds = nil
        generation &+= 1
        return next
    }
}
