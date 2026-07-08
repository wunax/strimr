import Foundation

struct AutomaticRefreshGate {
    private var hasStartedInitialLoad = false
    private var lastRefreshStartedAt: Date?
    private let debounceInterval: TimeInterval

    init(debounceInterval: TimeInterval = 90) {
        self.debounceInterval = debounceInterval
    }

    mutating func startInitialLoadIfNeeded() -> Bool {
        guard !hasStartedInitialLoad else { return false }
        hasStartedInitialLoad = true
        lastRefreshStartedAt = Date()
        return true
    }

    mutating func shouldRefresh(now: Date = Date(), isLoading: Bool) -> Bool {
        guard hasStartedInitialLoad, !isLoading else { return false }

        if let lastRefreshStartedAt,
           now.timeIntervalSince(lastRefreshStartedAt) < debounceInterval
        {
            return false
        }

        lastRefreshStartedAt = now
        return true
    }
}
