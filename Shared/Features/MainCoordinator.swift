
import Observation
import SwiftUI

@MainActor
@Observable
final class MainCoordinator {
    enum Tab: Hashable {
        case home
        case search
        case library
        case more
        case libraryDetail(String)
    }

    enum Route: Hashable {
        case mediaDetail(MediaItem)
        case downloads
        case seriesDownloadSelection(MediaItem)
    }

    var tab: Tab = .home
    var homePath = NavigationPath()
    var searchPath = NavigationPath()
    var libraryPath = NavigationPath()
    var morePath = NavigationPath()
    private var libraryDetailPaths: [String: NavigationPath] = [:]

    var selectedRatingKey: String?
    var selectedDownloadPath: String?
    var isPresentingPlayer = false
    var isPresentingUserMenu = false
    var shouldResumeFromOffset = true

    func pathBinding(for tab: Tab) -> Binding<NavigationPath> {
        Binding(
            get: {
                switch tab {
                case .home:
                    self.homePath
                case .search:
                    self.searchPath
                case .library:
                    self.libraryPath
                case .more:
                    self.morePath
                case let .libraryDetail(libraryId):
                    self.libraryDetailPaths[libraryId] ?? NavigationPath()
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
                case let .libraryDetail(libraryId):
                    self.libraryDetailPaths[libraryId] = newValue
                }
            }
        )
    }

    // MARK: - Navigation Actions

    func showMediaDetail(_ media: MediaItem) {
        let route = Route.mediaDetail(media)
        appendRoute(route)
    }

    func showMediaDetailReplacingDownloads(_ media: MediaItem) {
        isPresentingUserMenu = false
        let route = Route.mediaDetail(media)

        withCurrentPath { path in
            if !path.isEmpty {
                path.removeLast()
            } else {
                print("DEBUG: Path was empty, nothing removed.")
            }
            path.append(route)
        }
    }

    func showPlayer(for ratingKey: String, shouldResumeFromOffset: Bool = true, downloadPath: String? = nil) {
        selectedRatingKey = ratingKey
        self.shouldResumeFromOffset = shouldResumeFromOffset
        self.selectedDownloadPath = downloadPath
        isPresentingPlayer = true
    }

    func resetPlayer() {
        selectedRatingKey = nil
        selectedDownloadPath = nil
        isPresentingPlayer = false
        shouldResumeFromOffset = true
    }

    func showDownloads() {
        isPresentingUserMenu = false
        let route = Route.downloads
        appendRoute(route)
    }

    func replaceSelectionWithDownloads() {
        isPresentingUserMenu = false
        let route = Route.downloads

        withCurrentPath { path in
            if !path.isEmpty {
                path.removeLast()
            }
            path.append(route)
        }
    }

    func goBack() {
        withCurrentPath { path in
            if !path.isEmpty {
                path.removeLast()
            }
        }
    }

    func showSeriesDownloadSelection(for media: MediaItem) {
        isPresentingUserMenu = false
        let route = Route.seriesDownloadSelection(media)
        appendRoute(route)
    }

    // MARK: - Private Helper

    private func appendRoute(_ route: Route) {
        withCurrentPath { path in
            path.append(route)
        }
    }

    private func withCurrentPath(_ block: (inout NavigationPath) -> Void) {
        switch tab {
        case .home:
            block(&homePath)
        case .search:
            block(&searchPath)
        case .library:
            block(&libraryPath)
        case .more:
            block(&morePath)
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            block(&path)
            libraryDetailPaths[libraryId] = path
        }
    }
}
