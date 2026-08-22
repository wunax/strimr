import Combine
import SwiftUI

@MainActor
final class MainCoordinator: ObservableObject, PlaybackPresenting {
    private struct MediaRouteEntry {
        let mediaID: String
        let depth: Int
    }

    enum Tab: Hashable {
        case home
        case search
        case library
        case favorites
        case more
        case seerrDiscover
        case libraryDetail(String)
    }

    enum Route: Hashable {
        case mediaDetail(PlayableMediaItem)
        case collectionDetail(CollectionMediaItem)
        case playlistDetail(PlaylistMediaItem)
        case hubDetail(Hub)
        case personDetail(Person)
    }

    @Published var tab: Tab = .home
    @Published var homePath = NavigationPath()
    @Published var searchPath = NavigationPath()
    @Published var libraryPath = NavigationPath()
    @Published var favoritesPath = NavigationPath()
    @Published var morePath = NavigationPath()
    @Published var seerrDiscoverPath = NavigationPath()
    @Published private var libraryDetailPaths: [String: NavigationPath] = [:]
    private var mediaRouteEntries: [Tab: [MediaRouteEntry]] = [:]
    private var serverServices: [String: MediaServices] = [:]
    private var scopedServerIdentifiers: [Tab: String] = [:]

    @Published var isPresentingPlayer = false
    @Published var shouldResumeFromOffset = true
    @Published var selectedMediaQueue: PlaybackQueue?
    @Published var selectedMediaServices: MediaServices?

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
                case .favorites:
                    self.favoritesPath
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
                case .favorites:
                    self.favoritesPath = newValue
                case .more:
                    self.morePath = newValue
                case .seerrDiscover:
                    self.seerrDiscoverPath = newValue
                case let .libraryDetail(libraryId):
                    self.libraryDetailPaths[libraryId] = newValue
                }
                self.pruneMediaRouteEntries(for: tab, maximumDepth: newValue.count)
                if newValue.isEmpty {
                    self.scopedServerIdentifiers[tab] = nil
                }
            },
        )
    }

    func showMediaDetail(_ media: PlayableMediaItem) {
        let route = Route.mediaDetail(media)

        switch tab {
        case .home:
            homePath.append(route)
            recordMediaRoute(media, depth: homePath.count, tab: tab)
        case .search:
            searchPath.append(route)
            recordMediaRoute(media, depth: searchPath.count, tab: tab)
        case .library:
            libraryPath.append(route)
            recordMediaRoute(media, depth: libraryPath.count, tab: tab)
        case .favorites:
            favoritesPath.append(route)
            recordMediaRoute(media, depth: favoritesPath.count, tab: tab)
        case .more:
            morePath.append(route)
            recordMediaRoute(media, depth: morePath.count, tab: tab)
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
            recordMediaRoute(media, depth: path.count, tab: tab)
        }
    }

    func returnToSeries(_ series: PlayableMediaItem) {
        guard let destinationDepth = mediaRouteEntries[tab]?
            .last(where: { $0.mediaID == series.id })?
            .depth
        else {
            showMediaDetail(series)
            return
        }

        switch tab {
        case .home:
            pop(path: &homePath, to: destinationDepth, tab: tab)
        case .search:
            pop(path: &searchPath, to: destinationDepth, tab: tab)
        case .library:
            pop(path: &libraryPath, to: destinationDepth, tab: tab)
        case .favorites:
            pop(path: &favoritesPath, to: destinationDepth, tab: tab)
        case .more:
            pop(path: &morePath, to: destinationDepth, tab: tab)
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            pop(path: &path, to: destinationDepth, tab: tab)
            libraryDetailPaths[libraryId] = path
        }
    }

    private func recordMediaRoute(_ media: PlayableMediaItem, depth: Int, tab: Tab) {
        pruneMediaRouteEntries(for: tab, maximumDepth: depth - 1)
        mediaRouteEntries[tab, default: []].append(
            MediaRouteEntry(mediaID: media.id, depth: depth),
        )
    }

    private func pruneMediaRouteEntries(for tab: Tab, maximumDepth: Int) {
        mediaRouteEntries[tab]?.removeAll { $0.depth > maximumDepth }
    }

    private func pop(path: inout NavigationPath, to depth: Int, tab: Tab) {
        let numberOfRoutes = path.count - depth
        guard numberOfRoutes > 0 else { return }
        path.removeLast(numberOfRoutes)
        pruneMediaRouteEntries(for: tab, maximumDepth: depth)
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

    func showSearchResult(_ source: SearchResultSource) {
        serverServices[source.serverIdentifier] = source.services
        scopedServerIdentifiers[tab] = source.serverIdentifier
        showMediaDetail(source.media)
    }

    func services(for tab: Tab, default defaultServices: MediaServices) -> MediaServices {
        guard let identifier = scopedServerIdentifiers[tab] else { return defaultServices }
        return serverServices[identifier] ?? defaultServices
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
        case .favorites:
            favoritesPath.append(route)
        case .more:
            morePath.append(route)
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
        case .favorites:
            favoritesPath.append(route)
        case .more:
            morePath.append(route)
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
        }
    }

    func showHubDetail(_ hub: Hub) {
        let route = Route.hubDetail(hub)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .favorites:
            favoritesPath.append(route)
        case .more:
            morePath.append(route)
        case .seerrDiscover:
            break
        case let .libraryDetail(libraryId):
            var path = libraryDetailPaths[libraryId] ?? NavigationPath()
            path.append(route)
            libraryDetailPaths[libraryId] = path
        }
    }

    func showPersonDetail(_ person: Person) {
        let route = Route.personDetail(person)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .favorites, .more, .seerrDiscover:
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
        case .home, .search, .library, .favorites, .more:
            break
        case .libraryDetail:
            break
        }
    }

    func showPlayer(
        for queue: PlaybackQueue,
        services: MediaServices,
        shouldResumeFromOffset: Bool = true,
    ) {
        selectedMediaQueue = queue
        selectedMediaServices = services
        self.shouldResumeFromOffset = shouldResumeFromOffset
        isPresentingPlayer = true
    }

    func resetPlayer() {
        selectedMediaQueue = nil
        selectedMediaServices = nil
        isPresentingPlayer = false
        shouldResumeFromOffset = true
    }
}
