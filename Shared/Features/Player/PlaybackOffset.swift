import Foundation

/// A sync correction in whole milliseconds. Positive means later than the picture, for audio and
/// subtitles alike (AetherEngine's convention).
struct PlaybackOffset: Equatable, Sendable {
    static let zero = PlaybackOffset(milliseconds: 0)

    let milliseconds: Int

    var seconds: Double {
        Double(milliseconds) / 1000
    }

    var isZero: Bool {
        milliseconds == 0
    }
}

struct PlaybackOffsetRange: Sendable {
    let limitMilliseconds: Int
    let fineStepMilliseconds: Int
    let coarseStepMilliseconds: Int

    /// Must match AetherEngine's `AudioDelayPolicy.maxAbsSeconds`, which the engine does not expose.
    static let audio = PlaybackOffsetRange(limitMilliseconds: 2000, fineStepMilliseconds: 50, coarseStepMilliseconds: 250)
    static let subtitles = PlaybackOffsetRange(
        limitMilliseconds: 30000,
        fineStepMilliseconds: 100,
        coarseStepMilliseconds: 1000,
    )

    func clamp(_ milliseconds: Int) -> Int {
        min(max(milliseconds, -limitMilliseconds), limitMilliseconds)
    }

    func stepMilliseconds(coarse: Bool) -> Int {
        coarse ? coarseStepMilliseconds : fineStepMilliseconds
    }

    /// A step that would cross the limit stops on it rather than being refused.
    func stepped(_ offset: PlaybackOffset, by steps: Int, coarse: Bool) -> PlaybackOffset {
        let delta = steps.multipliedReportingOverflow(by: stepMilliseconds(coarse: coarse))
        guard !delta.overflow else {
            return PlaybackOffset(milliseconds: steps > 0 ? limitMilliseconds : -limitMilliseconds)
        }
        let sum = offset.milliseconds.addingReportingOverflow(delta.partialValue)
        guard !sum.overflow else {
            return PlaybackOffset(milliseconds: steps > 0 ? limitMilliseconds : -limitMilliseconds)
        }
        return PlaybackOffset(milliseconds: clamp(sum.partialValue))
    }

    func canStep(_ offset: PlaybackOffset, direction: Int) -> Bool {
        if direction > 0 {
            offset.milliseconds < limitMilliseconds
        } else if direction < 0 {
            offset.milliseconds > -limitMilliseconds
        } else {
            false
        }
    }
}

enum PlaybackOffsetKind: String, Hashable, Identifiable, Sendable {
    case audio
    case subtitles

    var id: String {
        rawValue
    }

    var range: PlaybackOffsetRange {
        switch self {
        case .audio: .audio
        case .subtitles: .subtitles
        }
    }
}

enum PlaybackOffsetFormatter {
    /// Values from this magnitude on are shown in seconds.
    static let secondsThresholdMilliseconds = 10000

    /// `+350 ms`, `-2400 ms`, `+12.5 s`, and `0 ms` without a sign. Units and decimal separator follow
    /// the locale.
    static func string(milliseconds: Int, locale: Locale = .current) -> String {
        if abs(milliseconds) < secondsThresholdMilliseconds {
            return Measurement(value: Double(milliseconds), unit: UnitDuration.milliseconds).formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.sign(strategy: .always(includingZero: false)).grouping(.never),
                ).locale(locale),
            )
        }
        return Measurement(value: Double(milliseconds) / 1000, unit: UnitDuration.seconds).formatted(
            .measurement(
                width: .abbreviated,
                usage: .asProvided,
                numberFormatStyle: .number.sign(strategy: .always(includingZero: false))
                    .precision(.fractionLength(1)),
            ).locale(locale),
        )
    }

    /// Label of a step button: a bare signed number for audio (`+50`), seconds for subtitles (`+0.1 s`).
    static func stepLabel(milliseconds: Int, kind: PlaybackOffsetKind, locale: Locale = .current) -> String {
        switch kind {
        case .audio:
            milliseconds.formatted(.number.sign(strategy: .always()).grouping(.never).locale(locale))
        case .subtitles:
            Measurement(value: Double(milliseconds) / 1000, unit: UnitDuration.seconds).formatted(
                .measurement(
                    width: .abbreviated,
                    usage: .asProvided,
                    numberFormatStyle: .number.sign(strategy: .always()).precision(.fractionLength(0 ... 1)),
                ).locale(locale),
            )
        }
    }
}

/// Why a sync correction cannot be applied to the current stream.
enum PlaybackOffsetAvailability: Hashable, Sendable {
    case available
    /// AVPlayer owns the media (native live HLS), the stream is audio only, or live without DVR.
    case unavailableForStream
    /// The server burns the subtitle into the picture.
    case burnedInSubtitles
    case noSubtitleTrack

    var isAvailable: Bool {
        self == .available
    }

    static func audio(isNativeBypass: Bool, isAudioOnly: Bool, isLiveWithoutDVR: Bool) -> Self {
        isNativeBypass || isAudioOnly || isLiveWithoutDVR ? .unavailableForStream : .available
    }

    static func subtitles(isNativeBypass: Bool, burnsSubtitles: Bool, hasActiveSubtitleTrack: Bool) -> Self {
        if isNativeBypass {
            return .unavailableForStream
        }
        if burnsSubtitles {
            return .burnedInSubtitles
        }
        return hasActiveSubtitleTrack ? .available : .noSubtitleTrack
    }
}

/// Holds the audio delay back until presses stop, so a burst costs the engine a single re-anchor.
struct AudioDelayDispatch {
    static let defaultDelay: Duration = .milliseconds(450)

    let delay: Duration
    private(set) var pendingMilliseconds: Int?
    private(set) var deadline: ContinuousClock.Instant?

    init(delay: Duration = Self.defaultDelay) {
        self.delay = delay
    }

    mutating func submit(_ milliseconds: Int, at now: ContinuousClock.Instant) {
        pendingMilliseconds = milliseconds
        deadline = now.advanced(by: delay)
    }

    /// The pending value once the quiet period has elapsed, consumed.
    mutating func takeIfDue(at now: ContinuousClock.Instant) -> Int? {
        guard let deadline, now >= deadline else { return nil }
        return flush()
    }

    /// The pending value right away, consumed. Used when the sync bar closes.
    mutating func flush() -> Int? {
        defer {
            pendingMilliseconds = nil
            deadline = nil
        }
        return pendingMilliseconds
    }
}

/// Press-and-hold repetition of a step button: every 300 ms, then 150 ms, then 75 ms.
enum PlaybackOffsetRepeat {
    static func interval(beforeRepeat index: Int) -> Duration {
        switch index {
        case ..<4: .milliseconds(300)
        case ..<12: .milliseconds(150)
        default: .milliseconds(75)
        }
    }
}
