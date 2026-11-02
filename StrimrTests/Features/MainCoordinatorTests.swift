import Foundation
@testable import Strimr
import SwiftUI
import Testing

@MainActor
struct MainCoordinatorTests {
    private func coordinator(startupScreen: StartupScreen, configure: (SettingsManager) -> Void = { _ in
    }) -> MainCoordinator {
        let settings = SettingsManager(userDefaults: TestDefaults.make())
        settings.setStartupScreen(startupScreen)
        configure(settings)
        return MainCoordinator(settingsManager: settings)
    }

    @Test func `opens on the chosen tab`() {
        #expect(coordinator(startupScreen: .home).tab == .home)
        #expect(coordinator(startupScreen: .search).tab == .search)
        #expect(coordinator(startupScreen: .libraries).tab == .library)
    }

    @Test func `falls back to Home when the chosen tab is hidden`() {
        let coordinator = coordinator(startupScreen: .favorites) { $0.setDisplayFavoritesTab(false) }

        #expect(coordinator.tab == .home)
    }

    @Test func `opens Live TV once it becomes available`() {
        let coordinator = coordinator(startupScreen: .liveTV)
        #expect(coordinator.tab == .home)

        coordinator.openPendingStartupTab(.seerrDiscover)
        #expect(coordinator.tab == .home)

        coordinator.openPendingStartupTab(.liveTV)
        #expect(coordinator.tab == .liveTV)
    }

    @Test func `does not switch tabs once the user has picked one`() {
        let coordinator = coordinator(startupScreen: .discover)

        coordinator.tab = .search
        coordinator.tab = .home
        coordinator.openPendingStartupTab(.seerrDiscover)

        #expect(coordinator.tab == .home)
    }

    @Test func `does not switch tabs once the user has browsed Home`() {
        let coordinator = coordinator(startupScreen: .discover)

        coordinator.homePath.append("detail")
        coordinator.homePath = NavigationPath()
        coordinator.openPendingStartupTab(.seerrDiscover)

        #expect(coordinator.tab == .home)
    }

    @Test func `does not switch tabs once something has been played`() {
        let coordinator = coordinator(startupScreen: .liveTV)

        coordinator.isPresentingPlayer = true
        coordinator.resetPlayer()
        coordinator.openPendingStartupTab(.liveTV)

        #expect(coordinator.tab == .home)
    }

    @Test func `does not open a hidden tab once it becomes available`() {
        let coordinator = coordinator(startupScreen: .liveTV) { $0.setDisplayLiveTVTab(false) }

        coordinator.openPendingStartupTab(.liveTV)

        #expect(coordinator.tab == .home)
    }
}
