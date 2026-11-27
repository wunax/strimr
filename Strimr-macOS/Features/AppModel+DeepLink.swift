import Foundation

extension AppModel: DeepLinkNavigating {
    var isShowingPlayer: Bool {
        playerPresentation != nil
    }

    func closePlayerForDeepLink() {
        resetPlayer()
    }

    func openDeepLinkTab(_ tab: DeepLink.Tab) {
        selection = switch tab {
        case .home: .home
        case .search: .search
        case .downloads: .downloads
        case .libraries: .libraries
        case .liveTV: .liveTV
        case .explore: .explore
        case .favorites: .favorites
        }
    }

    func showDeepLinkMedia(_ media: MediaItem) {
        selection = .home
        showMedia(media)
    }

    func showDeepLinkLibrary(_ library: Library) {
        selection = .libraries
        showLibrary(library)
    }
}
