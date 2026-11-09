import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackerWriteQueueTests {
    private let defaults = TestDefaults.make()

    private func write(
        _ item: TrackerItem,
        action: TrackerQueuedWrite.Action = .add,
        profile: String = "p1",
        service: TrackerService = .trakt,
    ) -> TrackerQueuedWrite {
        TrackerQueuedWrite(profileID: profile, service: service, action: action, item: item, watchedAt: nil)
    }

    @Test func `the latest intent about a row replaces the previous one`() {
        let queue = TrackerWriteQueue(userDefaults: defaults)

        queue.enqueue([write(TrackerFixtures.movie, action: .add)])
        queue.enqueue([write(TrackerFixtures.movie, action: .remove)])

        #expect(queue.writes.map(\.action) == [.remove])
    }

    @Test func `episodes of a series stay separate rows`() {
        let queue = TrackerWriteQueue(userDefaults: defaults)

        queue.enqueue([write(TrackerFixtures.episode(1)), write(TrackerFixtures.episode(2))])

        #expect(queue.writes.count == 2)
    }

    @Test func `services and profiles do not merge with each other`() {
        let queue = TrackerWriteQueue(userDefaults: defaults)

        queue.enqueue([
            write(TrackerFixtures.movie),
            write(TrackerFixtures.movie, service: .simkl),
            write(TrackerFixtures.movie, profile: "p2"),
        ])

        #expect(queue.pending(profileID: "p1", service: .trakt).count == 1)
        #expect(queue.pending(profileID: "p1", service: .simkl).count == 1)
        #expect(queue.pending(profileID: "p2", service: .trakt).count == 1)
    }

    @Test func `the oldest writes go first past the cap`() {
        let queue = TrackerWriteQueue(userDefaults: defaults)

        queue.enqueue((1 ... TrackerWriteQueue.maxCount + 5).map { write(TrackerFixtures.episode($0)) })

        #expect(queue.writes.count == TrackerWriteQueue.maxCount)
        #expect(queue.writes.first?.item.episode == 6)
    }

    @Test func `a write is dropped after too many failures`() throws {
        let queue = TrackerWriteQueue(userDefaults: defaults)
        queue.enqueue([write(TrackerFixtures.movie)])
        let id = try #require(queue.writes.first?.id)

        for _ in 1 ..< TrackerWriteQueue.maxAttempts {
            queue.recordFailure(ids: [id])
        }
        #expect(queue.writes.first?.attempts == TrackerWriteQueue.maxAttempts - 1)

        queue.recordFailure(ids: [id])
        #expect(queue.writes.isEmpty)
    }

    @Test func `writes survive a restart`() {
        TrackerWriteQueue(userDefaults: defaults).enqueue([write(TrackerFixtures.episode(4))])

        #expect(TrackerWriteQueue(userDefaults: defaults).writes.first?.item == TrackerFixtures.episode(4))
    }

    @Test func `removing a service leaves the others`() {
        let queue = TrackerWriteQueue(userDefaults: defaults)
        queue.enqueue([write(TrackerFixtures.movie), write(TrackerFixtures.movie, service: .simkl)])

        queue.removeAll(profileID: "p1", service: .trakt)

        #expect(queue.writes.map(\.service) == [.simkl])
    }
}
