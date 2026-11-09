import Foundation

nonisolated enum LibraryScrubberMapping {
    /// A finger at the top of the track reaches the first item and one at the bottom the last.
    static func index(forFraction fraction: Double, totalCount: Int) -> Int {
        guard totalCount > 1 else { return 0 }
        let clamped = min(max(fraction, 0), 1)
        return Int((clamped * Double(totalCount - 1)).rounded())
    }

    static func fraction(forIndex index: Int, totalCount: Int) -> Double {
        guard totalCount > 1 else { return 0 }
        return min(max(Double(index) / Double(totalCount - 1), 0), 1)
    }

    static func fraction(contentOffset: CGFloat, maximumOffset: CGFloat) -> Double {
        guard maximumOffset > 0 else { return 0 }
        return min(max(Double(contentOffset / maximumOffset), 0), 1)
    }
}

/// Limits the requests sent while the scrubber sweeps through the listing.
nonisolated struct LibraryScrubLoadThrottle {
    let interval: Duration
    private var lastLoad: ContinuousClock.Instant?

    init(interval: Duration = .milliseconds(200)) {
        self.interval = interval
    }

    mutating func shouldLoad(at now: ContinuousClock.Instant) -> Bool {
        if let lastLoad, now - lastLoad < interval {
            return false
        }
        lastLoad = now
        return true
    }

    mutating func reset() {
        lastLoad = nil
    }
}
