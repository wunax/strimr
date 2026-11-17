import Foundation
@testable import Strimr
import Testing

@MainActor
struct AutomaticMarkerSkipTests {
    private let intro = SkipSegment(id: "intro", kind: .intro, startTime: 10, endTime: 40)
    private let credits = SkipSegment(id: "credits", kind: .credits, startTime: 100, endTime: 120)
    private let allKinds: Set<SkipSegment.Kind> = [.intro, .credits, .commercial]

    private func play(
        _ skip: inout AutomaticMarkerSkip,
        through positions: [TimeInterval],
        countdownSeconds: Int = 5,
        enabledKinds: Set<SkipSegment.Kind>? = nil,
    ) -> [SkipSegment] {
        positions.compactMap {
            skip.update(
                position: $0,
                markers: [intro, credits],
                enabledKinds: enabledKinds ?? allKinds,
                countdownSeconds: countdownSeconds,
            )
        }
    }

    @Test func `without a countdown the marker is skipped as soon as it starts`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [9, 10], countdownSeconds: 0) == [intro])
        #expect(skip.countdown == nil)
    }

    @Test func `a skipped marker is not skipped again while playback is still inside it`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10, 40, 40], countdownSeconds: 0) == [intro])
    }

    @Test func `the countdown skips once enough playback has elapsed`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10, 11, 12, 13, 14]).isEmpty)
        #expect(skip.countdown?.marker == intro)
        #expect(play(&skip, through: [15]) == [intro])
        #expect(skip.countdown == nil)
    }

    @Test func `progress follows played time`() throws {
        var skip = AutomaticMarkerSkip()

        _ = play(&skip, through: [10, 11, 12])

        let countdown = try #require(skip.countdown)
        #expect(abs(countdown.progress - 0.4) < 0.0001)
        #expect(countdown.remainingSeconds == 3)
    }

    @Test func `the countdown waits while playback is paused`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10, 12, 12, 12, 12, 12, 12, 12]).isEmpty)
        #expect(skip.countdown?.position == 12)
    }

    @Test func `seeking within the marker cancels the countdown`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10, 11, 30, 31, 32, 33, 34, 35, 36]).isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `seeking back within the marker cancels the countdown`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [12, 13, 11, 12, 13, 14, 15, 16, 17]).isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `a cancelled marker counts down again after playback leaves and returns`() {
        var skip = AutomaticMarkerSkip()

        _ = play(&skip, through: [10, 11])
        skip.cancel()

        #expect(play(&skip, through: [12, 13, 14, 15, 16]).isEmpty)
        #expect(play(&skip, through: [5, 10, 11, 12, 13, 14, 15]) == [intro])
    }

    @Test func `seeking out of the marker drops the countdown`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10, 11, 60, 61, 62, 63, 64, 65]).isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `seeking into another marker starts a new countdown there`() {
        var skip = AutomaticMarkerSkip()

        _ = play(&skip, through: [10, 11])

        #expect(play(&skip, through: [100, 101, 102, 103, 104, 105]) == [credits])
    }

    @Test func `a marker that ends before the countdown is not skipped`() {
        var skip = AutomaticMarkerSkip()
        let short = SkipSegment(id: "short", kind: .intro, startTime: 10, endTime: 12)

        let skipped = [10.0, 11, 12, 13, 14, 15, 16].compactMap {
            skip.update(position: $0, markers: [short], enabledKinds: allKinds, countdownSeconds: 5)
        }

        #expect(skipped.isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `disabled kinds are left alone`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: Array(stride(from: 10.0, through: 20, by: 1)), enabledKinds: [.credits]).isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `turning a kind off cancels its countdown`() {
        var skip = AutomaticMarkerSkip()

        _ = play(&skip, through: [10, 11])
        #expect(play(&skip, through: [12, 13, 14, 15, 16], enabledKinds: [.credits]).isEmpty)
        #expect(skip.countdown == nil)
    }

    @Test func `reset forgets the marker already handled`() {
        var skip = AutomaticMarkerSkip()

        #expect(play(&skip, through: [10], countdownSeconds: 0) == [intro])
        skip.reset()

        #expect(play(&skip, through: [11], countdownSeconds: 0) == [intro])
    }
}
