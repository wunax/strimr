import AetherEngine
import Foundation

struct HomeContent {
    let continueWatching: Hub?
    let recentlyAdded: [Hub]
}

enum ArtworkResource {
    case url(URL)
    case data(Data)
}

struct MediaSearchSource {
    let serverIdentifier: String
    let serverName: String
    let media: MediaDisplayItem
    let services: MediaServices
}

struct MediaDetailContent {
    let media: MediaItem
    let parentSeries: MediaItem?
    let onDeck: MediaItem?
    let seasons: [MediaItem]
    let episodes: [MediaItem]
    let cast: [CastMember]
    let relatedHubs: [Hub]
}

struct MediaDownloadPreparation {
    let media: MediaItem
    let request: URLRequest
}

struct RemoteSubtitleResult: Hashable, Identifiable {
    let id: String
    let title: String
    let language: String?
    let codec: String
    let providerTitle: String?
}

@MainActor
protocol MediaHomeService: AnyObject {
    func loadHome(hiddenLibraryIDs: Set<String>, includesPlaylists: Bool) async throws -> HomeContent
}

@MainActor
protocol MediaLibraryService: AnyObject {
    func libraries() async throws -> [Library]
    func randomArtwork(for library: Library) async throws -> ArtworkResource?
    func recommended(in library: Library) async throws -> [Hub]
    func items(
        in library: Library,
        parentID: String?,
        startIndex: Int,
        limit: Int
    ) async throws -> MediaPage<MediaDisplayItem>
    func collections(in library: Library) async throws -> [CollectionMediaItem]
    func playlists(in library: Library) async throws -> [PlaylistMediaItem]
}

@MainActor
protocol MediaSearchService: AnyObject {
    func search(
        query: String,
        kinds: Set<MediaKind>,
        searchesAllServers: Bool
    ) async throws -> [MediaSearchSource]
}

@MainActor
protocol MediaArtworkService: AnyObject {
    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?
    ) async throws -> ArtworkResource?

    func artwork(
        path: String?,
        width: Int?,
        height: Int?
    ) async throws -> ArtworkResource?
}

@MainActor
protocol MediaDetailService: AnyObject {
    var supportsWatchlist: Bool { get }
    var supportsRemoteSubtitleSearch: Bool { get }
    func mediaItem(id: String) async throws -> MediaItem
    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?
    ) async throws -> [RemoteSubtitleResult]
    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws
    func details(for media: MediaItem) async throws -> MediaDetailContent
    func seasons(for series: MediaItem) async throws -> [MediaItem]
    func episodes(for season: MediaItem, seriesID: String?) async throws -> [MediaItem]
    func setPlayed(_ played: Bool, itemID: String) async throws
    func collectionItems(id: String) async throws -> [MediaDisplayItem]
    func playlistItems(id: String) async throws -> [MediaDisplayItem]
    func person(id: String) async throws -> Person
    func personMedia(id: String) async throws -> [MediaDisplayItem]
}

@MainActor
protocol MediaPlaybackService: AnyObject {
    func queue(startingWith itemID: String, kind: MediaKind, shuffle: Bool) async throws -> PlaybackQueue
    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue
    func prepare(media: MediaItem, resume: Bool) async throws -> PlaybackPlan
    func reportStarted(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws
    func reportProgress(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws
    func reportStopped(plan: PlaybackPlan, position: TimeInterval) async throws
    func externalSubtitles(media: MediaItem) async throws -> [ExternalSubtitleTrack]
}

@MainActor
protocol MediaDownloadService: AnyObject {
    func prepareDownload(itemID: String) async throws -> MediaDownloadPreparation
    func downloadableItems(itemID: String, kind: MediaKind) async throws -> [MediaItem]
}
