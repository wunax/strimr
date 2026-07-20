import Observation
import SwiftUI

@MainActor
@Observable
final class MacAppModel: PlaybackPresenting {
    static let playerWindowID = "player"

    private struct MediaRouteEntry {
        let mediaID: String
        let depth: Int
    }

    enum SidebarItem: Hashable, Identifiable {
        case home
        case discover
        case search
        case libraries
        case library(String)
        case settings

        var id: String {
            switch self {
            case .home: "home"
            case .discover: "discover"
            case .search: "search"
            case .libraries: "libraries"
            case let .library(id): "library-\(id)"
            case .settings: "settings"
            }
        }
    }

    enum Route: Hashable {
        case media(PlayableMediaItem)
        case collection(CollectionMediaItem)
        case playlist(PlaylistMediaItem)
        case hub(Hub)
        case library(Library)
        case seerr(SeerrMedia)
    }

    struct PlayerPresentation {
        let id = UUID()
        let playQueue: PlayQueueState
        let shouldResumeFromOffset: Bool
    }

    var selection: SidebarItem = .home
    var playerPresentation: PlayerPresentation?
    private var paths: [SidebarItem: NavigationPath] = [:]
    private var mediaRouteEntries: [SidebarItem: [MediaRouteEntry]] = [:]

    func pathBinding(for item: SidebarItem) -> Binding<NavigationPath> {
        Binding(
            get: { self.paths[item] ?? NavigationPath() },
            set: { newValue in
                self.paths[item] = newValue
                self.pruneMediaRouteEntries(for: item, maximumDepth: newValue.count)
            },
        )
    }

    func showMedia(_ media: MediaDisplayItem) {
        switch media {
        case let .playable(item):
            guard let playable = PlayableMediaItem(mediaItem: item) else { return }
            append(.media(playable))
        case let .collection(collection):
            append(.collection(collection))
        case let .playlist(playlist):
            append(.playlist(playlist))
        }
    }

    func showMedia(_ media: MediaItem) {
        guard let playable = PlayableMediaItem(mediaItem: media) else { return }
        append(.media(playable))
    }

    func returnToSeries(_ series: PlayableMediaItem) {
        guard let destinationDepth = mediaRouteEntries[selection]?
            .last(where: { $0.mediaID == series.id })?
            .depth
        else {
            append(.media(series))
            return
        }

        var path = paths[selection] ?? NavigationPath()
        let numberOfRoutes = path.count - destinationDepth
        guard numberOfRoutes > 0 else { return }
        path.removeLast(numberOfRoutes)
        paths[selection] = path
        pruneMediaRouteEntries(for: selection, maximumDepth: destinationDepth)
    }

    func showHub(_ hub: Hub) {
        append(.hub(hub))
    }

    func showLibrary(_ library: Library) {
        append(.library(library))
    }

    func showSeerr(_ media: SeerrMedia) {
        append(.seerr(media))
    }

    func showPlayer(for playQueue: PlayQueueState, shouldResumeFromOffset: Bool = true) {
        playerPresentation = PlayerPresentation(
            playQueue: playQueue,
            shouldResumeFromOffset: shouldResumeFromOffset,
        )
    }

    func resetPlayer() {
        playerPresentation = nil
    }

    private func append(_ route: Route) {
        var path = paths[selection] ?? NavigationPath()
        path.append(route)
        paths[selection] = path

        if case let .media(media) = route {
            pruneMediaRouteEntries(for: selection, maximumDepth: path.count - 1)
            mediaRouteEntries[selection, default: []].append(
                MediaRouteEntry(mediaID: media.id, depth: path.count),
            )
        }
    }

    private func pruneMediaRouteEntries(for item: SidebarItem, maximumDepth: Int) {
        mediaRouteEntries[item]?.removeAll { $0.depth > maximumDepth }
    }
}
