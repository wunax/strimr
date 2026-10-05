import Foundation
@testable import Strimr
import Testing

@MainActor
struct AggregationServiceTests {
    private struct Target {
        let server: ServerIdentity
        let isEligible: Bool
        let outcome: Result<Int, Error>
    }

    private struct ServerFailure: Error {}

    private let a = ServerIdentity(provider: .plex, id: "a")
    private let b = ServerIdentity(provider: .plex, id: "b")
    private let c = ServerIdentity(provider: .jellyfin, id: "c")
    private let d = ServerIdentity(provider: .jellyfin, id: "d")

    @Test func `partial results keep the servers that answered`() async {
        var transportFailures: [ServerIdentity] = []
        var captured: [Error] = []
        let service = AggregationService(
            reportTransportFailure: { transportFailures.append($0) },
            captureError: { captured.append($0) },
        )

        let result = await service.fanOut(
            targets: [
                Target(server: a, isEligible: true, outcome: .success(1)),
                Target(server: b, isEligible: true, outcome: .failure(URLError(.timedOut))),
                Target(server: c, isEligible: true, outcome: .failure(ServerFailure())),
                Target(server: d, isEligible: false, outcome: .success(4)),
            ],
            identity: \.server,
            services: { $0.isEligible ? $0 : nil },
        ) { target in
            try target.outcome.get()
        }

        #expect(result.value == [a: 1])
        #expect(result.succeeded == [a])
        #expect(result.failed == [b, c])
        #expect(result.skipped == [d])
        #expect(result.cancelled.isEmpty)
        #expect(transportFailures == [b])
        #expect(captured.count == 1)
    }

    @Test func `cancellation is not reported`() async {
        var captured: [Error] = []
        var transportFailures: [ServerIdentity] = []
        let service = AggregationService(
            reportTransportFailure: { transportFailures.append($0) },
            captureError: { captured.append($0) },
        )

        let result = await service.fanOut(
            targets: [
                Target(server: a, isEligible: true, outcome: .failure(CancellationError())),
                Target(server: b, isEligible: true, outcome: .failure(URLError(.cancelled))),
            ],
            identity: \.server,
            services: { $0 },
        ) { target in
            try target.outcome.get()
        }

        #expect(result.cancelled == [a, b])
        #expect(result.failed.isEmpty)
        #expect(captured.isEmpty)
        #expect(transportFailures.isEmpty)
    }

    @Test func `servers are queried in parallel`() async {
        let service = AggregationService(reportTransportFailure: { _ in }, captureError: { _ in })
        let tracker = ConcurrencyTracker()

        let result = await service.fanOut(
            targets: [a, b, c],
            identity: { $0 },
            services: { $0 },
        ) { _ in
            tracker.start()
            try await Task.sleep(for: .milliseconds(200))
            tracker.finish()
            return 1
        }

        #expect(result.succeeded == [a, b, c])
        #expect(tracker.maximum == 3)
    }

    @Test func `sessions that are not ready or disabled are skipped`() async {
        let service = AggregationService(reportTransportFailure: { _ in }, captureError: { _ in })
        let sessions = [
            ServerSession(identity: a, name: "A", accountID: "x", services: nil, isEnabled: true, status: .ready),
            ServerSession(identity: b, name: "B", accountID: "x", services: nil, isEnabled: false, status: .ready),
            ServerSession(identity: c, name: "C", accountID: "y", services: nil, isEnabled: true, status: .unreachable),
        ]

        let result = await service.fanOut(servers: sessions) { _ in 1 }

        #expect(result.skipped == [a, b, c])
        #expect(result.value.isEmpty)
    }
}

@MainActor
private final class ConcurrencyTracker {
    private var current = 0
    private(set) var maximum = 0

    func start() {
        current += 1
        maximum = max(maximum, current)
    }

    func finish() {
        current -= 1
    }
}
