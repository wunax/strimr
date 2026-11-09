import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackerPlaybackTests {
    private let item = TrackerFixtures.movie

    private final class Clock {
        var date = Date(timeIntervalSince1970: 1000)
    }

    private let clock = Clock()

    private func channel(
        client: FakeTrackerClient,
        isAvailable: @escaping @MainActor () -> Bool = { true },
        onFailure: @escaping TrackerPlaybackChannel.FailureHandler = { _, _ in },
    ) -> TrackerPlaybackChannel {
        let clock = clock
        return TrackerPlaybackChannel(
            client: client,
            isAvailable: isAvailable,
            onFailure: onFailure,
            sleep: { _ in },
            now: { clock.date },
        )
    }

    private func report(
        _ event: TrackerPlaybackEvent,
        item: TrackerItem? = nil,
        progress: Double = 10,
    ) -> TrackerPlaybackReport {
        TrackerPlaybackReport(event: event, item: item ?? self.item, progress: progress, date: clock.date)
    }

    // MARK: - Channel

    @Test func `a stop then a start stay in order`() async {
        let client = FakeTrackerClient()
        let channel = channel(client: client)

        channel.send(report(.stop, item: TrackerFixtures.episode(1)))
        channel.send(report(.start, item: TrackerFixtures.episode(2)))
        await channel.flush()

        #expect(client.reports.map(\.event) == [.stop, .start])
    }

    @Test func `only the last start or pause is kept while waiting`() async {
        let client = FakeTrackerClient()
        let channel = channel(client: client)

        channel.send(report(.start))
        channel.send(report(.pause, progress: 20))
        channel.send(report(.start, progress: 30))
        channel.send(report(.pause, progress: 40))
        await channel.flush()

        #expect(client.reports.map(\.progress) == [40])
    }

    @Test func `a stop is never merged away`() async {
        let client = FakeTrackerClient()
        let channel = channel(client: client)

        channel.send(report(.start))
        channel.send(report(.pause))
        channel.send(report(.stop, progress: 90))
        await channel.flush()

        #expect(client.reports.last == .init(event: .stop, item: item, progress: 90))
    }

    @Test func `the same state resent too soon is ignored`() async {
        let client = FakeTrackerClient(resendThrottle: 30)
        let channel = channel(client: client)

        channel.send(report(.start))
        await channel.flush()
        clock.date.addTimeInterval(10)
        channel.send(report(.start))
        await channel.flush()
        #expect(client.reports.count == 1)

        clock.date.addTimeInterval(30)
        channel.send(report(.start))
        await channel.flush()
        #expect(client.reports.count == 2)
    }

    @Test func `a stop is sent even right after another`() async {
        let client = FakeTrackerClient()
        let channel = channel(client: client)

        channel.send(report(.stop))
        await channel.flush()
        channel.send(report(.stop))
        await channel.flush()

        #expect(client.reports.count == 2)
    }

    @Test func `a conflict counts as already recorded`() async {
        let client = FakeTrackerClient()
        client.reportFailures = [TrackerAPIError.conflict]
        var failures = 0
        let channel = channel(client: client, onFailure: { _, _ in failures += 1 })

        channel.send(report(.stop))
        await channel.flush()

        #expect(failures == 0)
    }

    @Test func `an unknown title stops being reported`() async {
        let client = FakeTrackerClient()
        client.reportFailures = [TrackerAPIError.notFound]
        let channel = channel(client: client)

        channel.send(report(.start))
        await channel.flush()
        channel.send(report(.stop))
        await channel.flush()

        #expect(client.reports.isEmpty)
    }

    @Test func `the write lock is waited out`() async {
        let client = FakeTrackerClient()
        client.reportFailures = [TrackerAPIError.writeLocked, TrackerAPIError.writeLocked]
        let channel = channel(client: client)

        channel.send(report(.stop))
        await channel.flush()

        #expect(client.reports.map(\.event) == [.stop])
    }

    @Test func `the write lock gives up after a few attempts`() async {
        let client = FakeTrackerClient()
        client.reportFailures = Array(repeating: TrackerAPIError.writeLocked, count: 5)
        var failures = 0
        let channel = channel(client: client, onFailure: { _, _ in failures += 1 })

        channel.send(report(.stop))
        await channel.flush()

        #expect(failures == 1)
    }

    @Test func `nothing is sent while the service is on hold`() async {
        let client = FakeTrackerClient()
        var errors: [Error] = []
        let channel = channel(client: client, isAvailable: { false }, onFailure: { _, error in errors.append(error) })

        channel.send(report(.stop))
        await channel.flush()

        #expect(client.reports.isEmpty)
        #expect(errors.first as? TrackerAPIError == .unavailable)
    }

    // MARK: - Session

    private func session(
        client: FakeTrackerClient,
        resumeOffset: TimeInterval? = nil,
    ) -> (TrackerPlaybackSession, TrackerBinding) {
        let binding = TrackerBinding(profileID: "p", service: client.service, client: client)
        binding.channel = channel(client: client)
        let session = TrackerPlaybackSession(resumeOffset: resumeOffset) { [clock] in clock.date }
        return (session, binding)
    }

    @Test func `playback states become start, pause and stop`() async {
        let client = FakeTrackerClient(resendThrottle: 0)
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 100, duration: 1000)
        await binding.channel.flush()
        session.paused(position: 200, duration: 1000)
        await binding.channel.flush()
        session.playing(position: 200, duration: 1000)
        await binding.channel.flush()
        session.stopped(position: 500, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.map(\.event) == [.start, .pause, .start, .stop])
        #expect(client.reports.map(\.progress) == [10, 20, 20, 50])
    }

    @Test func `repeated states send nothing`() async {
        let client = FakeTrackerClient(resendThrottle: 0)
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 100, duration: 1000)
        session.playing(position: 110, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.count == 1)
    }

    @Test func `a pause before any playback sends nothing`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.paused(position: 0, duration: 1000)
        session.stopped(position: 0, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.isEmpty)
    }

    @Test func `a stop without a start sends nothing`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.stopped(position: 500, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.isEmpty)
    }

    @Test func `a stop below one percent sends nothing, which trakt would reject`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 0, duration: 1000)
        await binding.channel.flush()
        session.stopped(position: 5, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.map(\.event) == [.start])
    }

    @Test func `a natural end reports a full progress`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 900, duration: 1000)
        await binding.channel.flush()
        session.finished()
        session.stopped(position: 950, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.map(\.event) == [.start, .stop])
        #expect(client.reports.last?.progress == 100)
    }

    @Test func `an unknown duration sends nothing`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 100, duration: nil)
        await binding.channel.flush()

        #expect(client.reports.isEmpty)
    }

    @Test func `the first start uses the resume point, as the player reports 0 before seeking`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client, resumeOffset: 300)
        session.resolve(item: item, bindings: [binding])

        session.playing(position: 0, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.first?.progress == 30)
    }

    @Test func `events before the ids are known keep their position`() async {
        let client = FakeTrackerClient(resendThrottle: 0)
        let (session, binding) = session(client: client)

        session.playing(position: 100, duration: 1000)
        session.paused(position: 200, duration: 1000)
        session.resolve(item: item, bindings: [binding])
        await binding.channel.flush()

        #expect(client.reports.last?.event == .pause)
        #expect(client.reports.last?.progress == 20)
    }

    @Test func `an item without ids reports nothing`() async {
        let client = FakeTrackerClient()
        let (session, binding) = session(client: client)
        session.resolve(item: nil, bindings: [binding])

        session.playing(position: 100, duration: 1000)
        await binding.channel.flush()

        #expect(client.reports.isEmpty)
    }
}
