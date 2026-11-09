import Foundation

nonisolated struct TrackerPlaybackReport: Equatable, Sendable {
    let event: TrackerPlaybackEvent
    let item: TrackerItem
    let progress: Double
    let date: Date
}

/// One service's real-time reports, delivered in order and one at a time. It outlives a playback, so the stop of an
/// episode and the start of the next stay in order.
@MainActor
final class TrackerPlaybackChannel {
    typealias FailureHandler = @MainActor (TrackerPlaybackReport, Error) -> Void
    typealias Sleep = @Sendable (Duration) async throws -> Void

    /// Simkl holds a write lock for 20 seconds, which these attempts wait out.
    private static let writeLockAttempts = 5
    private static let writeLockDelay: Duration = .seconds(5)

    private let client: any TrackerClient
    private let isAvailable: @MainActor () -> Bool
    private let onFailure: FailureHandler
    private let sleep: Sleep
    private let now: () -> Date

    private var pending: [TrackerPlaybackReport] = []
    private var drainTask: Task<Void, Never>?
    private var lastSent: TrackerPlaybackReport?
    private var unmatchedItems: Set<TrackerItem> = []

    init(
        client: any TrackerClient,
        isAvailable: @escaping @MainActor () -> Bool,
        onFailure: @escaping FailureHandler,
        sleep: @escaping Sleep = { try await Task.sleep(for: $0) },
        now: @escaping () -> Date = Date.init,
    ) {
        self.client = client
        self.isAvailable = isAvailable
        self.onFailure = onFailure
        self.sleep = sleep
        self.now = now
    }

    func send(_ report: TrackerPlaybackReport) {
        guard !unmatchedItems.contains(report.item) else { return }
        if report.event != .stop {
            if let last = pending.last, last.event != .stop, last.item == report.item {
                pending[pending.count - 1] = report
                return
            }
            if pending.isEmpty, let lastSent, lastSent.event == report.event, lastSent.item == report.item,
               report.date.timeIntervalSince(lastSent.date) < client.policy.resendThrottle
            {
                return
            }
        }
        pending.append(report)
        guard drainTask == nil else { return }
        drainTask = Task { [weak self] in
            await self?.drain()
        }
    }

    /// Waits for the reports sent so far.
    func flush() async {
        await drainTask?.value
    }

    private func drain() async {
        while !pending.isEmpty {
            await deliver(pending.removeFirst())
        }
        drainTask = nil
    }

    private func deliver(_ report: TrackerPlaybackReport) async {
        guard isAvailable() else {
            onFailure(report, TrackerAPIError.unavailable)
            return
        }
        for attempt in 1 ... Self.writeLockAttempts {
            do {
                try await client.report(report.event, item: report.item, progress: report.progress)
                lastSent = report
                return
            } catch TrackerAPIError.conflict {
                lastSent = report
                return
            } catch TrackerAPIError.notFound {
                unmatchedItems.insert(report.item)
                return
            } catch TrackerAPIError.writeLocked where attempt < Self.writeLockAttempts {
                try? await sleep(Self.writeLockDelay)
            } catch {
                onFailure(report, error)
                return
            }
        }
    }
}

/// One playback, pinned to the accounts active when it began. Forwards state changes only: no timer, no seeks, which
/// neither service wants, and Simkl's free quota of 500 requests a day would not survive.
@MainActor
final class TrackerPlaybackSession {
    private enum Phase {
        case idle
        case playing
        case paused
    }

    private enum Action {
        case playing(position: TimeInterval, duration: TimeInterval?)
        case paused(position: TimeInterval, duration: TimeInterval?)
        case stopped(position: TimeInterval, duration: TimeInterval?)
        case finished
    }

    private let resumeOffset: TimeInterval?
    private let now: () -> Date
    /// Retained here so the playback keeps its accounts after a profile switch.
    private var targets: [TrackerBinding] = []
    private var item: TrackerItem?
    private var isResolved = false
    private var buffered: [(action: Action, date: Date)] = []
    private var phase = Phase.idle
    private var hasStarted = false

    init(resumeOffset: TimeInterval?, now: @escaping () -> Date = Date.init) {
        self.resumeOffset = resumeOffset
        self.now = now
    }

    /// Ids resolve over the network, so events that arrive before then are replayed with their original position.
    func resolve(item: TrackerItem?, bindings: [TrackerBinding]) {
        self.item = item
        targets = item == nil ? [] : bindings
        isResolved = true
        let events = buffered
        buffered = []
        for event in events {
            apply(event.action, date: event.date)
        }
    }

    func playing(position: TimeInterval, duration: TimeInterval?) {
        record(.playing(position: position, duration: duration))
    }

    func paused(position: TimeInterval, duration: TimeInterval?) {
        record(.paused(position: position, duration: duration))
    }

    func stopped(position: TimeInterval, duration: TimeInterval?) {
        record(.stopped(position: position, duration: duration))
    }

    func finished() {
        record(.finished)
    }

    private func record(_ action: Action) {
        guard isResolved else {
            buffered.append((action, now()))
            return
        }
        apply(action, date: now())
    }

    private func apply(_ action: Action, date: Date) {
        switch action {
        case let .playing(position, duration):
            guard phase != .playing else { return }
            phase = .playing
            // The player reports position 0 before it seeks to the resume point.
            let effective = !hasStarted && position < 1 ? resumeOffset ?? position : position
            hasStarted = true
            send(.start, progress: Self.progress(effective, duration), date: date)
        case let .paused(position, duration):
            guard phase == .playing else { return }
            phase = .paused
            send(.pause, progress: Self.progress(position, duration), date: date)
        case let .stopped(position, duration):
            guard phase != .idle else { return }
            phase = .idle
            // Trakt answers 422 below 1%, and a stop this early says nothing worth reporting.
            guard let progress = Self.progress(position, duration), progress >= 1 else { return }
            send(.stop, progress: progress, date: date)
        case .finished:
            guard phase != .idle else { return }
            phase = .idle
            send(.stop, progress: 100, date: date)
        }
    }

    private func send(_ event: TrackerPlaybackEvent, progress: Double?, date: Date) {
        guard let item, let progress else { return }
        for target in targets {
            target.channel.send(TrackerPlaybackReport(event: event, item: item, progress: progress, date: date))
        }
    }

    private static func progress(_ position: TimeInterval, _ duration: TimeInterval?) -> Double? {
        guard let duration, duration > 0 else { return nil }
        return (position / duration * 100).trackerProgress
    }
}
