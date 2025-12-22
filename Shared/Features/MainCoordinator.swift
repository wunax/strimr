import Combine
import SwiftUI

@MainActor
final class MainCoordinator: ObservableObject {
    enum Tab {
        case home
        case search
        case library
        case more
    }

    enum Route: Hashable {
        case mediaDetail(MediaItem)
    }

    @Published var tab: Tab = .home
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var morePath = NavigationPath()

    @Published var selectedRatingKey: String?
    @Published var isPresentingPlayer = false

    func pathBinding(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: {
                switch tab {
                case .home:
                    return self.homePath
                case .search:
                    return self.searchPath
                case .library:
                    return self.libraryPath
                case .more:
                    return self.morePath
                }
            },
            set: { newValue in
                switch tab {
                case .home:
                    self.homePath = newValue
                case .search:
                    self.searchPath = newValue
                case .library:
                    self.libraryPath = newValue
                case .more:
                    self.morePath = newValue
                }
            }
        )
    }

    func showMediaDetail(_ media: MediaItem) {
        let route = Route.mediaDetail(media)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .more:
            break
        }
    }

    func showPlayer(for ratingKey: String) {
        selectedRatingKey = ratingKey
        isPresentingPlayer = true
    }

    func resetPlayer() {
        selectedRatingKey = nil
        isPresentingPlayer = false
    }
}
