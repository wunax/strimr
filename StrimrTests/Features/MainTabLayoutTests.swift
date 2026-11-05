@testable import Strimr
import Testing

@MainActor
struct MainTabLayoutTests {
    private let fourTabs: [MainCoordinator.Tab] = [.home, .seerrDiscover, .downloads, .library]
    private let sixTabs: [MainCoordinator.Tab] = [.home, .seerrDiscover, .downloads, .library, .liveTV, .favorites]

    @Test func `keeps every tab in the bar when they fit`() {
        let layout = MainTabLayout(tabs: fourTabs, isCompact: true)

        #expect(layout.bar == fourTabs)
        #expect(layout.overflow.isEmpty)
    }

    @Test func `moves the last tabs to More when they do not fit`() {
        let layout = MainTabLayout(tabs: sixTabs, isCompact: true)

        #expect(layout.bar == [.home, .seerrDiscover, .downloads])
        #expect(layout.overflow == [.library, .liveTV, .favorites])
    }

    @Test func `keeps every tab in the bar outside of a compact layout`() {
        let layout = MainTabLayout(tabs: sixTabs, isCompact: false)

        #expect(layout.bar == sixTabs)
        #expect(layout.overflow.isEmpty)
    }
}
