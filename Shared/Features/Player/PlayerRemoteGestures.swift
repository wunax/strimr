import Foundation

/// What a center click does while the tvOS player controls are hidden.
enum PlayerCenterClickResult: Equatable {
    /// A contextual action such as "Skip Intro" holds the focus and handles the click itself.
    case activateContextualAction
    case resumeFromPauseScreen
    case togglePlayPause
    case showControls

    static func resolve(
        setting: PlayerCenterClickAction,
        hasContextualAction: Bool,
        isPauseScreenPresented: Bool,
    ) -> PlayerCenterClickResult {
        if hasContextualAction {
            return .activateContextualAction
        }
        if isPauseScreenPresented {
            return .resumeFromPauseScreen
        }
        switch setting {
        case .playPause: return .togglePlayPause
        case .showControls: return .showControls
        }
    }
}

/// A scrub on the tvOS timeline: it previews a position until a click commits it, and Back cancels it.
struct PlayerScrubSession {
    /// Presses closer together than this keep accelerating.
    static let accelerationWindow: TimeInterval = 0.4
    static let maximumMultiplier = 5

    private(set) var origin: Double?
    private var consecutiveMoves = 0
    private var lastMoveDate: Date?

    var isActive: Bool {
        origin != nil
    }

    /// Returns whether the scrub just started.
    mutating func begin(at position: Double) -> Bool {
        guard origin == nil else { return false }
        origin = position
        consecutiveMoves = 0
        lastMoveDate = nil
        return true
    }

    /// The position one press away, with presses in quick succession moving further each time.
    mutating func step(
        from position: Double,
        forward: Bool,
        stepSize: Double,
        upperBound: Double,
        at date: Date = Date(),
    ) -> Double {
        if let lastMoveDate, date.timeIntervalSince(lastMoveDate) > Self.accelerationWindow {
            consecutiveMoves = 0
        }
        lastMoveDate = date
        consecutiveMoves = min(consecutiveMoves + 1, Self.maximumMultiplier)
        let delta = stepSize * Double(consecutiveMoves)
        return forward ? min(upperBound, position + delta) : max(0, position - delta)
    }

    /// Ends the scrub so the previewed position applies. Returns whether a scrub was running.
    mutating func commit() -> Bool {
        defer { reset() }
        return origin != nil
    }

    /// Ends the scrub without applying it, and returns where it started.
    mutating func cancel() -> Double? {
        defer { reset() }
        return origin
    }

    private mutating func reset() {
        origin = nil
        consecutiveMoves = 0
        lastMoveDate = nil
    }
}
