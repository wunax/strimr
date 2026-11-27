import Foundation

extension MainCoordinator: DeepLinkNavigating {
    var isShowingPlayer: Bool {
        isPresentingPlayer
    }

    var playerCoversPages: Bool {
        true
    }

    func closePlayerForDeepLink() {
        resetPlayer()
    }

    func openDeepLinkTab(_ tab: DeepLink.Tab) {
        switch tab {
        case .home:
            self.tab = .home
        case .search:
            self.tab = .search
        case .downloads:
            #if os(tvOS)
                self.tab = .home
            #else
                self.tab = .downloads
            #endif
        case .libraries:
            self.tab = .library
        case .liveTV:
            self.tab = .liveTV
        case .explore:
            self.tab = .explore
        case .favorites:
            self.tab = .favorites
        }
    }

    func showDeepLinkMedia(_ media: MediaItem) {
        tab = .home
        showMediaDetail(media)
    }

    func showDeepLinkLibrary(_ library: Library) {
        showLibrary(library)
    }
}
