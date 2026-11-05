/// Splits the iOS tabs between the tab bar and the More tab.
struct MainTabLayout: Equatable {
    /// A compact tab bar holds five items at most, the search button included. Past that, UIKit would add its own
    /// More controller, which wraps the tab's navigation stack in a second navigation bar.
    private static let maximumCompactTabCount = 4

    let bar: [MainCoordinator.Tab]
    let overflow: [MainCoordinator.Tab]

    init(tabs: [MainCoordinator.Tab], isCompact: Bool) {
        guard isCompact, tabs.count > Self.maximumCompactTabCount else {
            bar = tabs
            overflow = []
            return
        }
        let barCount = Self.maximumCompactTabCount - 1
        bar = Array(tabs.prefix(barCount))
        overflow = Array(tabs.dropFirst(barCount))
    }
}
