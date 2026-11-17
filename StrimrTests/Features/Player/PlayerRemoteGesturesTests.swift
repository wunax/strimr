import Foundation
@testable import Strimr
import Testing

struct PlayerRemoteGesturesTests {
    @Test func `center click follows the setting while nothing else claims it`() {
        #expect(resolve(.playPause) == .togglePlayPause)
        #expect(resolve(.showControls) == .showControls)
    }

    @Test func `contextual action takes the click before the setting and the pause screen`() {
        #expect(resolve(.playPause, contextual: true, pauseScreen: true) == .activateContextualAction)
        #expect(resolve(.showControls, contextual: true) == .activateContextualAction)
    }

    @Test func `center click on the pause screen resumes whatever the setting`() {
        #expect(resolve(.playPause, pauseScreen: true) == .resumeFromPauseScreen)
        #expect(resolve(.showControls, pauseScreen: true) == .resumeFromPauseScreen)
    }

    @Test func `cancelling a scrub returns where it started`() {
        var session = PlayerScrubSession()
        let started = session.begin(at: 120)
        _ = session.step(from: 120, forward: true, stepSize: 10, upperBound: 600)
        let origin = session.cancel()

        #expect(started)
        #expect(origin == 120)
        #expect(!session.isActive)
    }

    @Test func `committing a scrub keeps the previewed position`() {
        var session = PlayerScrubSession()
        _ = session.begin(at: 120)
        let target = session.step(from: 120, forward: true, stepSize: 10, upperBound: 600)
        let committed = session.commit()
        let originAfterCommit = session.cancel()

        #expect(committed)
        #expect(target == 130)
        #expect(originAfterCommit == nil)
    }

    @Test func `a running scrub keeps its origin`() {
        var session = PlayerScrubSession()
        let first = session.begin(at: 120)
        let second = session.begin(at: 300)

        #expect(first)
        #expect(!second)
        #expect(session.origin == 120)
    }

    @Test func `quick presses accelerate up to five steps and slow ones start over`() {
        var session = PlayerScrubSession()
        _ = session.begin(at: 0)
        let start = Date(timeIntervalSinceReferenceDate: 0)
        var position = 0.0
        var deltas: [Double] = []
        for press in 0 ..< 7 {
            let next = session.step(
                from: position, forward: true, stepSize: 10, upperBound: 10000,
                at: start.addingTimeInterval(Double(press) * 0.1),
            )
            deltas.append(next - position)
            position = next
        }
        #expect(deltas == [10, 20, 30, 40, 50, 50, 50])

        let afterPause = session.step(
            from: position, forward: false, stepSize: 10, upperBound: 10000, at: start.addingTimeInterval(5),
        )
        #expect(position - afterPause == 10)
    }

    @Test func `steps stay within the video`() {
        var session = PlayerScrubSession()
        _ = session.begin(at: 5)
        let backward = session.step(from: 5, forward: false, stepSize: 10, upperBound: 600)
        let forward = session.step(from: 595, forward: true, stepSize: 10, upperBound: 600)

        #expect(backward == 0)
        #expect(forward == 600)
    }

    private func resolve(
        _ setting: PlayerCenterClickAction,
        contextual: Bool = false,
        pauseScreen: Bool = false,
    ) -> PlayerCenterClickResult {
        PlayerCenterClickResult.resolve(
            setting: setting,
            hasContextualAction: contextual,
            isPauseScreenPresented: pauseScreen,
        )
    }
}
