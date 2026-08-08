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
    @Published var morePath = NavigationPath()
    @Published var seerrDiscoverPath = NavigationPath()
    @Published private var libraryDetailPaths: [String: NavigationPath] = [:]
    private var mediaRouteEntries: [Tab: [MediaRouteEntry]] = [:]
    private var serverContexts: [String: PlexAPIContext] = [:]
    private var scopedServerIdentifiers: [Tab: String] = [:]

    @Published var selectedPlayQueue: PlayQueueState?
    @Published var isPresentingPlayer = false
    @Published var shouldResumeFromOffset = true
    @Published var selectedPlaybackContext: PlexAPIContext?

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
        case .more:
            break
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
        case .more, .seerrDiscover:
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
        serverContexts[source.serverIdentifier] = source.context
        scopedServerIdentifiers[tab] = source.serverIdentifier
        showMediaDetail(source.media)
    }

    func context(for tab: Tab, default defaultContext: PlexAPIContext) -> PlexAPIContext {
        guard let identifier = scopedServerIdentifiers[tab] else { return defaultContext }
        return serverContexts[identifier] ?? defaultContext
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

    func showHubDetail(_ hub: Hub) {
        let route = Route.hubDetail(hub)

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

    func showPersonDetail(_ person: Person) {
        let route = Route.personDetail(person)

        switch tab {
        case .home:
            homePath.append(route)
        case .search:
            searchPath.append(route)
        case .library:
            libraryPath.append(route)
        case .more, .seerrDiscover:
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
        case .libraryDetail:
            break
        }
    }

    func showPlayer(
        for playQueue: PlayQueueState,
        context: PlexAPIContext,
        shouldResumeFromOffset: Bool = true,
    ) {
        selectedPlayQueue = playQueue
        selectedPlaybackContext = context
        self.shouldResumeFromOffset = shouldResumeFromOffset
        isPresentingPlayer = true
    }

    func resetPlayer() {
        selectedPlayQueue = nil
        selectedPlaybackContext = nil
        isPresentingPlayer = false
        shouldResumeFromOffset = true
    }
}
