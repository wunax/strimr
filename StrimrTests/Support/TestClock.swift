import Foundation

/// A clock that only moves when the test calls `advance(by:)`, so delays are checked without waiting for real time.
final nonisolated class TestClock: Clock, @unchecked Sendable {
    struct Instant: InstantProtocol {
        var offset: Duration

        func advanced(by duration: Duration) -> Instant {
            Instant(offset: offset + duration)
        }

        func duration(to other: Instant) -> Duration {
            other.offset - offset
        }

        static func < (lhs: Instant, rhs: Instant) -> Bool {
            lhs.offset < rhs.offset
        }
    }

    private struct Sleeper {
        let deadline: Instant
        let continuation: CheckedContinuation<Void, Error>
    }

    private let lock = NSLock()
    private var current = Instant(offset: .zero)
    private var sleepers: [UUID: Sleeper] = [:]
    private var cancelled: Set<UUID> = []

    var now: Instant {
        lock.withLock { current }
    }

    var minimumResolution: Duration {
        .zero
    }

    func sleep(until deadline: Instant, tolerance _: Duration?) async throws {
        let id = UUID()
        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let outcome: Result<Void, Error>? = lock.withLock {
                    // The cancellation handler can run before the sleeper is registered.
                    if cancelled.remove(id) != nil {
                        return .failure(CancellationError())
                    }
                    if deadline <= current {
                        return .success(())
                    }
                    sleepers[id] = Sleeper(deadline: deadline, continuation: continuation)
                    return nil
                }
                if let outcome {
                    continuation.resume(with: outcome)
                }
            }
        } onCancel: {
            let sleeper = lock.withLock {
                guard let sleeper = sleepers.removeValue(forKey: id) else {
                    cancelled.insert(id)
                    return Sleeper?.none
                }
                return sleeper
            }
            sleeper?.continuation.resume(throwing: CancellationError())
        }
    }

    /// Lets tasks that were just started reach their sleep, moves time forward, wakes every sleeper whose deadline
    /// passed, then lets the woken tasks run.
    func advance(by duration: Duration) async {
        await Self.yieldToPendingTasks()
        let due = lock.withLock {
            current = current.advanced(by: duration)
            let due = sleepers.filter { $0.value.deadline <= current }
            for id in due.keys {
                sleepers[id] = nil
            }
            return due.values.sorted { $0.deadline < $1.deadline }
        }
        for sleeper in due {
            sleeper.continuation.resume()
        }
        await Self.yieldToPendingTasks()
    }

    private static func yieldToPendingTasks() async {
        for _ in 0 ..< 10 {
            await Task.yield()
        }
    }
}
