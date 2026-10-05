import Foundation
@testable import Strimr
import Testing

struct PlaybackOffsetTests {
    private let english = Locale(identifier: "en_US")
    private let french = Locale(identifier: "fr_FR")

    @Test func `audio range matches the engine limit and steps`() {
        let range = PlaybackOffsetRange.audio

        #expect(range.limitMilliseconds == 2000)
        #expect(range.stepped(.zero, by: 1, coarse: false) == PlaybackOffset(milliseconds: 50))
        #expect(range.stepped(.zero, by: 1, coarse: true) == PlaybackOffset(milliseconds: 250))
        #expect(range.stepped(.zero, by: -3, coarse: false) == PlaybackOffset(milliseconds: -150))
    }

    @Test func `subtitle range steps by a tenth and a whole second`() {
        let range = PlaybackOffsetRange.subtitles

        #expect(range.limitMilliseconds == 30000)
        #expect(range.stepped(.zero, by: 1, coarse: false) == PlaybackOffset(milliseconds: 100))
        #expect(range.stepped(.zero, by: -1, coarse: true) == PlaybackOffset(milliseconds: -1000))
    }

    @Test func `a coarse step near the limit stops on it`() {
        let range = PlaybackOffsetRange.audio

        #expect(range.stepped(PlaybackOffset(milliseconds: 1900), by: 1, coarse: true).milliseconds == 2000)
        #expect(range.stepped(PlaybackOffset(milliseconds: -1900), by: -1, coarse: true).milliseconds == -2000)
        #expect(range.stepped(PlaybackOffset(milliseconds: 2000), by: 1, coarse: false).milliseconds == 2000)
    }

    @Test func `stepping cannot overflow`() {
        let range = PlaybackOffsetRange.subtitles

        #expect(range.stepped(.zero, by: .max, coarse: true).milliseconds == 30000)
        #expect(range.stepped(.zero, by: .min, coarse: true).milliseconds == -30000)
    }

    @Test func `clamp bounds both signs`() {
        let range = PlaybackOffsetRange.audio

        #expect(range.clamp(5000) == 2000)
        #expect(range.clamp(-5000) == -2000)
        #expect(range.clamp(-350) == -350)
    }

    @Test func `step buttons are disabled at the limit`() {
        let range = PlaybackOffsetRange.audio

        #expect(!range.canStep(PlaybackOffset(milliseconds: 2000), direction: 1))
        #expect(range.canStep(PlaybackOffset(milliseconds: 2000), direction: -1))
        #expect(!range.canStep(PlaybackOffset(milliseconds: -2000), direction: -1))
        #expect(range.canStep(.zero, direction: 1))
    }

    @Test func `stepping back to zero resets the offset`() {
        let range = PlaybackOffsetRange.subtitles
        let offset = range.stepped(.zero, by: 3, coarse: false)

        #expect(range.stepped(offset, by: -3, coarse: false).isZero)
    }

    @Test func `formats milliseconds with a visible sign`() {
        #expect(format(350, english) == "+350 ms")
        #expect(format(-2400, english) == "-2400 ms")
        #expect(format(9900, english) == "+9900 ms")
    }

    @Test func `formats zero without a sign`() {
        #expect(format(0, english) == "0 ms")
    }

    @Test func `switches to seconds from ten seconds`() {
        #expect(format(10000, english) == "+10.0 sec")
        #expect(format(-12500, english) == "-12.5 sec")
        #expect(format(12500, french) == "+12,5 s")
    }

    @Test func `formats step labels per kind`() {
        #expect(normalized(PlaybackOffsetFormatter.stepLabel(milliseconds: -250, kind: .audio, locale: english)) == "-250")
        #expect(normalized(PlaybackOffsetFormatter.stepLabel(milliseconds: 50, kind: .audio, locale: english)) == "+50")
        #expect(normalized(PlaybackOffsetFormatter.stepLabel(milliseconds: 100, kind: .subtitles, locale: french))
            == "+0,1 s")
        #expect(normalized(PlaybackOffsetFormatter.stepLabel(milliseconds: -1000, kind: .subtitles, locale: french))
            == "-1 s")
    }

    @Test func `audio is unavailable when the engine cannot move its timestamps`() {
        #expect(PlaybackOffsetAvailability.audio(isNativeBypass: false, isAudioOnly: false, isLiveWithoutDVR: false)
            == .available)
        #expect(PlaybackOffsetAvailability.audio(isNativeBypass: true, isAudioOnly: false, isLiveWithoutDVR: false)
            == .unavailableForStream)
        #expect(PlaybackOffsetAvailability.audio(isNativeBypass: false, isAudioOnly: true, isLiveWithoutDVR: false)
            == .unavailableForStream)
        #expect(PlaybackOffsetAvailability.audio(isNativeBypass: false, isAudioOnly: false, isLiveWithoutDVR: true)
            == .unavailableForStream)
    }

    @Test func `subtitles need an active track the app draws`() {
        #expect(PlaybackOffsetAvailability.subtitles(
            isNativeBypass: false,
            burnsSubtitles: false,
            hasActiveSubtitleTrack: true,
        ) == .available)
        #expect(PlaybackOffsetAvailability.subtitles(
            isNativeBypass: false,
            burnsSubtitles: false,
            hasActiveSubtitleTrack: false,
        ) == .noSubtitleTrack)
        #expect(PlaybackOffsetAvailability.subtitles(
            isNativeBypass: false,
            burnsSubtitles: true,
            hasActiveSubtitleTrack: false,
        ) == .burnedInSubtitles)
        #expect(PlaybackOffsetAvailability.subtitles(
            isNativeBypass: true,
            burnsSubtitles: false,
            hasActiveSubtitleTrack: true,
        ) == .unavailableForStream)
    }

    @Test func `hold repetition accelerates`() {
        #expect(PlaybackOffsetRepeat.interval(beforeRepeat: 0) == .milliseconds(300))
        #expect(PlaybackOffsetRepeat.interval(beforeRepeat: 4) == .milliseconds(150))
        #expect(PlaybackOffsetRepeat.interval(beforeRepeat: 12) == .milliseconds(75))
    }

    private func format(_ milliseconds: Int, _ locale: Locale) -> String {
        normalized(PlaybackOffsetFormatter.string(milliseconds: milliseconds, locale: locale))
    }

    private func normalized(_ string: String) -> String {
        string
            .replacingOccurrences(of: "\u{00A0}", with: " ")
            .replacingOccurrences(of: "\u{202F}", with: " ")
    }
}

struct AudioDelayDispatchTests {
    private let start = ContinuousClock.now

    @Test func `a burst of presses produces a single send`() {
        var dispatch = AudioDelayDispatch()
        dispatch.submit(50, at: start)
        dispatch.submit(100, at: start + .milliseconds(200))
        dispatch.submit(150, at: start + .milliseconds(400))

        #expect(dispatch.takeIfDue(at: start + .milliseconds(800)) == nil)
        #expect(dispatch.takeIfDue(at: start + .milliseconds(850)) == 150)
        #expect(dispatch.takeIfDue(at: start + .milliseconds(2000)) == nil)
    }

    @Test func `closing the bar forces the pending send`() {
        var dispatch = AudioDelayDispatch()
        dispatch.submit(-250, at: start)

        #expect(dispatch.flush() == -250)
        #expect(dispatch.takeIfDue(at: start + .seconds(1)) == nil)
    }

    @Test func `closing the bar with nothing pending sends nothing`() {
        var dispatch = AudioDelayDispatch()

        #expect(dispatch.flush() == nil)
    }
}
