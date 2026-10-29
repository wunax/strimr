import Foundation
@testable import Strimr
import Testing

@MainActor
struct DoubleTapSeekTests {
    private let commitDelay = Duration.milliseconds(100)
    private let start = ContinuousClock.now
    private let clock = TestClock()

    private func makeSeek() -> (DoubleTapSeek, () -> [DoubleTapSeek.Pending]) {
        let seek = DoubleTapSeek(doubleTapWindow: .milliseconds(300), commitDelay: commitDelay, clock: clock)
        var commits: [DoubleTapSeek.Pending] = []
        seek.onCommit = { commits.append($0) }
        return (seek, { commits })
    }

    private func at(_ milliseconds: Int) -> ContinuousClock.Instant {
        start + .milliseconds(milliseconds)
    }

    @Test(arguments: [
        (0.0, DoubleTapSeekZone.backward),
        (32.0, .backward),
        (34.0, .center),
        (66.0, .center),
        (67.0, .forward),
        (100.0, .forward),
    ])
    func `zones split the width in thirds`(x: Double, zone: DoubleTapSeekZone) {
        #expect(DoubleTapSeekZone(x: x, width: 100) == zone)
    }

    @Test func `an unknown width falls back to the center`() {
        #expect(DoubleTapSeekZone(x: 10, width: 0) == .center)
    }

    @Test func `a single tap is left to the caller`() {
        let (seek, _) = makeSeek()

        #expect(!seek.registerTap(in: .forward, at: at(0)))
        #expect(seek.pending == nil)
    }

    @Test func `a double tap on a side starts a seek`() {
        let (seek, _) = makeSeek()

        _ = seek.registerTap(in: .backward, at: at(0))

        #expect(seek.registerTap(in: .backward, at: at(200)))
        #expect(seek.pending == .init(forward: false, steps: 1))
    }

    @Test func `taps too far apart are not a double tap`() {
        let (seek, _) = makeSeek()

        _ = seek.registerTap(in: .forward, at: at(0))

        #expect(!seek.registerTap(in: .forward, at: at(400)))
        #expect(seek.pending == nil)
    }

    @Test func `taps on different zones are not a double tap`() {
        let (seek, _) = makeSeek()

        _ = seek.registerTap(in: .backward, at: at(0))

        #expect(!seek.registerTap(in: .forward, at: at(100)))
        #expect(seek.pending == nil)
    }

    @Test func `double taps in the center are left to the caller`() {
        let (seek, _) = makeSeek()

        #expect(!seek.registerTap(in: .center, at: at(0)))
        #expect(!seek.registerTap(in: .center, at: at(100)))
    }

    @Test func `single taps on the same side keep adding to the seek`() {
        let (seek, _) = makeSeek()
        _ = seek.registerTap(in: .forward, at: at(0))
        _ = seek.registerTap(in: .forward, at: at(100))

        #expect(seek.registerTap(in: .forward, at: at(600)))
        #expect(seek.registerTap(in: .forward, at: at(1100)))
        #expect(seek.pending == .init(forward: true, steps: 3))
    }

    @Test func `the seek is applied once after tapping stops`() async {
        let (seek, commits) = makeSeek()
        _ = seek.registerTap(in: .forward, at: at(0))
        _ = seek.registerTap(in: .forward, at: at(100))
        _ = seek.registerTap(in: .forward, at: at(200))

        await clock.advance(by: commitDelay * 3)

        #expect(commits() == [.init(forward: true, steps: 2)])
        #expect(seek.pending == nil)
    }

    @Test func `a single tap after the seek is applied is left to the caller`() async {
        let (seek, _) = makeSeek()
        _ = seek.registerTap(in: .forward, at: at(0))
        _ = seek.registerTap(in: .forward, at: at(100))

        await clock.advance(by: commitDelay * 3)

        #expect(!seek.registerTap(in: .forward, at: at(150)))
    }

    @Test func `tapping the other side applies the seek and switches direction`() {
        let (seek, commits) = makeSeek()
        _ = seek.registerTap(in: .forward, at: at(0))
        _ = seek.registerTap(in: .forward, at: at(100))
        _ = seek.registerTap(in: .forward, at: at(200))

        #expect(seek.registerTap(in: .backward, at: at(300)))
        #expect(commits() == [.init(forward: true, steps: 2)])
        #expect(seek.pending == .init(forward: false, steps: 1))
    }

    @Test func `tapping the center applies the seek and is left to the caller`() {
        let (seek, commits) = makeSeek()
        _ = seek.registerTap(in: .backward, at: at(0))
        _ = seek.registerTap(in: .backward, at: at(100))

        #expect(!seek.registerTap(in: .center, at: at(200)))
        #expect(commits() == [.init(forward: false, steps: 1)])
        #expect(seek.pending == nil)
    }

    @Test func `cancelling drops the pending seek`() async {
        let (seek, commits) = makeSeek()
        _ = seek.registerTap(in: .forward, at: at(0))
        _ = seek.registerTap(in: .forward, at: at(100))

        seek.cancel()
        await clock.advance(by: commitDelay * 3)

        #expect(commits().isEmpty)
        #expect(seek.pending == nil)
    }
}
