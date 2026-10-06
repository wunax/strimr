import Foundation
@testable import Strimr
import Testing

@MainActor
struct SleepTimerTests {
    private final class Clock {
        var now = Date(timeIntervalSince1970: 1_000_000)
    }

    private final class Playback {
        var isActive = true
        var pauseCount = 0
        var attenuations: [Float] = []
    }

    private let clock = Clock()
    private let playback = Playback()

    private func makeTimer() -> SleepTimer {
        let clock = clock
        let playback = playback
        let timer = SleepTimer(now: { clock.now })
        timer.pausePlayback = { playback.pauseCount += 1 }
        timer.isPlaybackActive = { playback.isActive }
        timer.setVolumeAttenuation = { playback.attenuations.append($0) }
        return timer
    }

    private func chapter(_ index: Int, from start: TimeInterval, to end: TimeInterval) -> MediaChapter {
        MediaChapter(
            id: "\(index)",
            title: "Chapter \(index)",
            index: index,
            startTime: start,
            endTime: end,
            image: nil,
            thumbPath: nil,
        )
    }

    @Test func `a duration counts down from now and extends by fifteen minutes`() {
        let timer = makeTimer()
        defer { timer.cancel() }

        timer.start(.duration(minutes: 30))
        #expect(timer.deadline == clock.now.addingTimeInterval(30 * 60))

        timer.extend()
        #expect(timer.deadline == clock.now.addingTimeInterval(45 * 60))
    }

    @Test func `boundary modes have no deadline to extend`() {
        let timer = makeTimer()

        timer.start(.endOfItem)
        timer.extend()

        #expect(timer.deadline == nil)
        #expect(timer.mode == .endOfItem)
    }

    @Test func `expiring while playing asks whether someone is still watching`() {
        let timer = makeTimer()
        defer { timer.cancel() }
        timer.start(.duration(minutes: 15))

        timer.expire()

        #expect(timer.promptDeadline == clock.now.addingTimeInterval(30))
        #expect(timer.deadline == nil)
        #expect(playback.pauseCount == 0)
    }

    @Test func `continuing restarts the full duration`() {
        let timer = makeTimer()
        defer { timer.cancel() }
        timer.start(.duration(minutes: 15))
        timer.extend()
        timer.expire()
        clock.now.addTimeInterval(10)

        timer.continueAfterPrompt()

        #expect(!timer.isPromptPresented)
        #expect(timer.mode == .duration(minutes: 15))
        #expect(timer.deadline == clock.now.addingTimeInterval(15 * 60))
    }

    @Test func `an unanswered prompt pauses and turns the timer off`() {
        let timer = makeTimer()
        timer.start(.duration(minutes: 15))
        timer.expire()

        timer.expirePrompt()

        #expect(playback.pauseCount == 1)
        #expect(!timer.isActive)
        #expect(!timer.isPromptPresented)
    }

    @Test func `expiring while already paused ends quietly`() {
        let timer = makeTimer()
        playback.isActive = false
        timer.start(.duration(minutes: 15))

        timer.expire()

        #expect(!timer.isPromptPresented)
        #expect(!timer.isActive)
        #expect(playback.pauseCount == 1)
    }

    @Test func `pausing by hand answers the prompt`() {
        let timer = makeTimer()
        timer.start(.duration(minutes: 15))
        timer.expire()

        timer.handlePlaybackStateChange(isPaused: true)

        #expect(!timer.isActive)
        #expect(playback.pauseCount == 0)
    }

    @Test func `pausing by hand keeps a running countdown`() {
        let timer = makeTimer()
        defer { timer.cancel() }
        timer.start(.duration(minutes: 15))

        timer.handlePlaybackStateChange(isPaused: true)

        #expect(timer.deadline != nil)
    }

    @Test func `the end of an item fades out then pauses just before the end`() {
        let timer = makeTimer()
        timer.start(.endOfItem)

        for position in [90.0, 92, 94, 96.5, 98] {
            timer.handlePosition(position, duration: 100, chapters: [])
        }
        #expect(playback.attenuations == [0.5, 0.2])
        #expect(playback.pauseCount == 0)

        timer.handlePosition(99.2, duration: 100, chapters: [])
        #expect(playback.pauseCount == 1)
        #expect(!timer.isActive)

        timer.handlePlaybackStateChange(isPaused: false)
        #expect(playback.attenuations.last == 1)
    }

    @Test func `a seek past the pause point does not pause`() {
        let timer = makeTimer()
        timer.start(.endOfItem)

        timer.handlePosition(50, duration: 100, chapters: [])
        timer.handlePosition(99.5, duration: 100, chapters: [])

        #expect(playback.pauseCount == 0)
        #expect(timer.isActive)
    }

    @Test func `seeking back out of the fade restores the volume`() {
        let timer = makeTimer()
        timer.start(.endOfItem)

        timer.handlePosition(96, duration: 100, chapters: [])
        timer.handlePosition(97, duration: 100, chapters: [])
        timer.handlePosition(40, duration: 100, chapters: [])

        #expect(playback.attenuations == [0.4, 1])
        #expect(timer.isActive)
    }

    @Test func `the end of a chapter pauses before the next chapter starts`() {
        let timer = makeTimer()
        timer.start(.endOfChapter)
        let chapters = [chapter(0, from: 0, to: 300), chapter(1, from: 300, to: 600)]

        timer.handlePosition(297, duration: 600, chapters: chapters)
        var boundaryPauses = 0
        timer.onBoundaryPause = { boundaryPauses += 1 }
        timer.handlePosition(299.1, duration: 600, chapters: chapters)

        #expect(playback.pauseCount == 1)
        #expect(boundaryPauses == 1)
        #expect(!timer.isActive)
    }

    @Test func `reaching the end claims it only for boundary modes`() {
        let boundaryTimer = makeTimer()
        boundaryTimer.start(.endOfChapter)
        #expect(boundaryTimer.consumePlaybackEnd())
        #expect(!boundaryTimer.isActive)

        let durationTimer = makeTimer()
        defer { durationTimer.cancel() }
        durationTimer.start(.duration(minutes: 30))
        #expect(!durationTimer.consumePlaybackEnd())
        #expect(durationTimer.isActive)
    }

    @Test func `live playback only offers durations`() {
        let live = SleepTimerMode.available(isLive: true, hasChapters: true)
        #expect(live == SleepTimerMode.durationMinutes.map { .duration(minutes: $0) })

        let withoutChapters = SleepTimerMode.available(isLive: false, hasChapters: false)
        #expect(withoutChapters.first == .endOfItem)
        #expect(!withoutChapters.contains(.endOfChapter))

        let withChapters = SleepTimerMode.available(isLive: false, hasChapters: true)
        #expect(withChapters.prefix(2) == [.endOfItem, .endOfChapter])
    }
}
