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

    // MARK: More tab

    private let compactLayout = MainTabLayout(
        tabs: [.home, .seerrDiscover, .downloads, .library, .liveTV],
        isCompact: true,
    )
    private let regularLayout = MainTabLayout(
        tabs: [.home, .seerrDiscover, .downloads, .library, .liveTV],
        isCompact: false,
    )
    private let library = Library(
        id: "1",
        title: "Movies",
        type: .movie,
        server: ServerIdentity(provider: .jellyfin, id: "server-1"),
    )

    @Test func `opens an overflow tab inside More`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)

        coordinator.tab = .library

        #expect(coordinator.tab == .more)
        #expect(coordinator.morePath.count == 1)
    }

    @Test func `leaves a tab of the bar selected`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)

        coordinator.tab = .downloads

        #expect(coordinator.tab == .downloads)
        #expect(coordinator.morePath.isEmpty)
    }

    @Test func `moves the startup tab to More once it overflows`() {
        let coordinator = coordinator(startupScreen: .libraries)

        coordinator.updateTabLayout(compactLayout)

        #expect(coordinator.tab == .more)
        #expect(coordinator.morePath.count == 1)
    }

    @Test func `opens Live TV inside More once it becomes available`() {
        let coordinator = coordinator(startupScreen: .liveTV)
        coordinator.updateTabLayout(compactLayout)

        coordinator.openPendingStartupTab(.liveTV)

        #expect(coordinator.tab == .more)
        #expect(coordinator.morePath.count == 1)
    }

    @Test func `shows a library in the More stack when the Libraries tab overflows`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)

        coordinator.showLibrary(library)

        #expect(coordinator.tab == .more)
        #expect(coordinator.morePath.count == 2)
        #expect(coordinator.libraryPath.isEmpty)
    }

    @Test func `shows a library in its own tab when it fits in the bar`() {
        let coordinator = coordinator(startupScreen: .home)

        coordinator.showLibrary(library)

        #expect(coordinator.tab == .library)
        #expect(coordinator.libraryPath.count == 1)
        #expect(coordinator.morePath.isEmpty)
    }

    @Test func `pushes details on the More stack while in More`() throws {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)
        coordinator.tab = .library
        let server = ServerIdentity(provider: .jellyfin, id: "server-1")
        let media = try #require(PlayableMediaItem(mediaItem: MediaItem.make(id: "1", server: server, type: .movie)))

        coordinator.showMediaDetail(media)

        #expect(coordinator.morePath.count == 2)
        #expect(coordinator.homePath.isEmpty)
    }

    @Test func `returns to the tab shown in More when the bar has room again`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)
        coordinator.tab = .library

        coordinator.updateTabLayout(regularLayout)

        #expect(coordinator.tab == .library)
        #expect(coordinator.morePath.isEmpty)
    }

    @Test func `leaves More for Home when its tab is gone and the bar has room`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(compactLayout)
        coordinator.tab = .liveTV

        coordinator.updateTabLayout(MainTabLayout(tabs: [.home, .downloads, .library], isCompact: true))

        #expect(coordinator.tab == .home)
        #expect(coordinator.morePath.isEmpty)
    }

    @Test func `closes a tab removed from More`() {
        let coordinator = coordinator(startupScreen: .home)
        coordinator.updateTabLayout(MainTabLayout(
            tabs: [.home, .seerrDiscover, .downloads, .library, .liveTV, .favorites],
            isCompact: true,
        ))
        coordinator.tab = .favorites

        coordinator.updateTabLayout(compactLayout)

        #expect(coordinator.tab == .more)
        #expect(coordinator.morePath.isEmpty)
    }
}
