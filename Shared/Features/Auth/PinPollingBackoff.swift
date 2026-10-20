import Foundation

struct PinPollingBackoff {
    static let baseInterval: Duration = .seconds(2)
    static let maxInterval: Duration = .seconds(10)

    private(set) var interval = Self.baseInterval

    mutating func recordResponse() {
        interval = Self.baseInterval
    }

    mutating func recordRateLimit() {
        interval = min(interval * 2, Self.maxInterval)
    }
}
