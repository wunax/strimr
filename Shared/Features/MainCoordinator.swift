import Combine
import SwiftUI

@MainActor
final class MainCoordinator: ObservableObject {
    enum Tab: Hashable {
        case home
        case search
        case library
        case more
        case seerrDiscover
        case libraryDetail(String)
    }

    enum Route: Hashable {
        case mediaDetail(PlayableMediaItem)
        case collectionDetail(CollectionMediaItem)
        case playlistDetail(PlaylistMediaItem)
    }

    @Published var tab: Tab = .home
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var morePath = NavigationPath()
    @Published var seerrDiscoverPath = NavigationPath()
    @Published private var libraryDetailPaths: [String: NavigationPath] = [:]

    @Published var selectedPlayQueue: PlayQueueState?
    @Published var isPresentingPlayer = false
    @Published var shouldResumeFromOffset = true

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
                case .seerrDiscover:
                    self.seerrDiscoverPath
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
                case .seerrDiscover:
                    self.seerrDiscoverPath = newValue
                case let .libraryDetail(libraryId):
                    self.libraryDetailPaths[libraryId] = newValue
                }
            },
        )
    }

    func showMediaDetail(_ media: PlayableMediaItem) {
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
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
        }
    }

    func showMediaDetail(_ media: MediaItem) {
        guard let playable = PlayableMediaItem(mediaItem: media) else { return }
        showMediaDetail(playable)
    }

    func showMediaDetail(_ media: MediaDisplayItem) {
        switch media {
        case let .playable(item):
            guard let playable = PlayableMediaItem(mediaItem: item) else { return }
            showMediaDetail(playable)
        case let .collection(collection):
            showCollectionDetail(collection)
        case let .playlist(playlist):
            showPlaylistDetail(playlist)
        }
    }

    func showCollectionDetail(_ collection: CollectionMediaItem) {
        let route = Route.collectionDetail(collection)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .more:
            break
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
        }
    }

    func showPlaylistDetail(_ playlist: PlaylistMediaItem) {
        let route = Route.playlistDetail(playlist)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .more:
            break
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
        }
    }

    func showSeerrMediaDetail(_ media: SeerrMedia) {
        switch tab {
        case .seerrDiscover:
            seerrDiscoverPath.append(media)
        case .home, .search, .library, .more:
            break
        case .libraryDetail(_):
            break
        }
    }

    func showPlayer(for playQueue: PlayQueueState, shouldResumeFromOffset: Bool = true) {
        selectedPlayQueue = playQueue
        self.shouldResumeFromOffset = shouldResumeFromOffset
        isPresentingPlayer = true
    }

    func resetPlayer() {
        selectedPlayQueue = nil
        isPresentingPlayer = false
        shouldResumeFromOffset = true
    }
}
