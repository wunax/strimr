import AetherEngine
import Foundation

struct HomeContent {
    let rows: [HomeRow]
}

enum ArtworkResource {
    case url(URL)
    case data(Data)
}

/// What a library tile shows: a few backdrops from the library, which it cycles through, and how many titles it holds.
struct LibraryPreview {
    static let artworkCount = 4

    let artworks: [ArtworkResource]
    let itemCount: Int?
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

struct MediaTrackSelection {
    let itemID: String
    let filePath: String?
    let audioTracks: [MediaTrackMetadata]
    let subtitleTracks: [MediaTrackMetadata]
    let selectedAudioTrackID: Int?
    let selectedSubtitleTrackID: Int?
    let versions: [MediaFileVersion]
    let versionID: String?
    /// The version "Automatic" would pick, shown under that option.
    let defaultVersionID: String?
}

struct MediaDownloadPreparation {
    let media: MediaItem
    let requestedQuality: TranscodeQualityPreset
    let effectiveQuality: TranscodeQualityPreset
    let request: URLRequest?
    let remoteReference: MediaDownloadRemoteReference?
    let sidecars: [MediaDownloadSidecar]
    let audioTitle: String?
    let subtitleTitle: String?
    let versionID: String?
    let versionLabel: String?
}

struct MediaTrackPreference: Codable, Hashable, Sendable {
    var audioStreamIndex: Int?
    var audioLanguage: String?
    var audioTitle: String?
    var audioCodec: String?
    var audioIsHearingImpaired: Bool?
    var audioIsCommentary: Bool?
    var subtitle: MediaSubtitlePreference

    nonisolated static let serverDefault = MediaTrackPreference(
        audioStreamIndex: nil,
        audioLanguage: nil,
        audioTitle: nil,
        audioCodec: nil,
        audioIsHearingImpaired: nil,
        audioIsCommentary: nil,
        subtitle: .serverDefault,
    )

    nonisolated var matchingAcrossItems: MediaTrackPreference {
        var preference = self
        preference.audioStreamIndex = nil
        if case let .track(_, language, title, codec, isForced, isHearingImpaired) = subtitle {
            preference.subtitle = .track(
                streamIndex: nil,
                language: language,
                title: title,
                codec: codec,
                isForced: isForced,
                isHearingImpaired: isHearingImpaired,
            )
        }
        return preference
    }
}

struct PlaybackStreamSelection: Sendable, Hashable {
    let audioStreamIndex: Int?
    let subtitleStreamIndex: Int?
    let subtitleIsOff: Bool
}

enum MediaSubtitlePreference: Codable, Hashable, Sendable {
    case serverDefault
    case off
    case track(
        streamIndex: Int?,
        language: String?,
        title: String?,
        codec: String,
        isForced: Bool,
        isHearingImpaired: Bool?,
    )
}

@MainActor
protocol MediaTrackSelectionMemoryService: AnyObject {
    func enableTrackSelectionMemory(for kind: PlaybackTrackKind) async throws
}

struct MediaDownloadSidecar {
    let request: URLRequest
    let fileExtension: String
    let title: String?
    let language: String?
    let codec: String
    let isForced: Bool
}

enum MediaDownloadRemoteReference: Codable, Hashable, Sendable {
    case plex(queueID: Int, itemID: Int)
    case jellyfin(playSessionID: String)
}

enum MediaDownloadPreparationUpdate {
    case preparing(progress: Double?)
    case ready(request: URLRequest, sidecars: [MediaDownloadSidecar])
    case failed(message: String)
}

enum MediaServerAccessRecoveryError: Error, Equatable {
    case accountUnauthorized
    case serverUnavailable
    case connectionFailed
}

enum ItemPlaybackReportState: Sendable {
    case started
    case progress
    case stopped
}

/// Watch state as reported by the server, used to resolve offline progress conflicts.
struct ServerItemWatchState: Sendable {
    let viewOffset: TimeInterval?
    let viewCount: Int
    let isPlayed: Bool
    let lastViewedAt: Date?
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
    /// `shownRowIDs` are the rows the user turned on that the server does not put on its home.
    func loadHome(
        hiddenLibraryIDs: Set<String>,
        includesPlaylists: Bool,
        shownRowIDs: Set<String>,
    ) async throws -> HomeContent
    /// Every row the user can add to the home, including the ones the server does not put there.
    func homeRowCatalog(hiddenLibraryIDs: Set<String>) async throws -> [HomeRow]
    func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem>
}

extension MediaHomeService {
    func homeRowCatalog(hiddenLibraryIDs _: Set<String>) async throws -> [HomeRow] {
        []
    }
}

@MainActor
protocol MediaLibraryService: AnyObject {
    func libraries() async throws -> [Library]
    func preview(for library: Library) async throws -> LibraryPreview?
    func recommended(in library: Library) async throws -> [Hub]
    func items(
        in library: Library,
        parentID: String?,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem>
    func collections(in library: Library) async throws -> [CollectionMediaItem]
    func playlists(in library: Library) async throws -> [PlaylistMediaItem]
}

@MainActor
protocol MediaSearchService: AnyObject {
    func search(query: String, kinds: Set<MediaKind>) async throws -> [MediaDisplayItem]
}

@MainActor
protocol MediaArtworkService: AnyObject {
    func artworkURL(path: String?, width: Int?, height: Int?) -> URL?

    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?,
    ) async throws -> ArtworkResource?

    func artwork(
        path: String?,
        width: Int?,
        height: Int?,
    ) async throws -> ArtworkResource?

    /// Theme path of an item, for providers that do not include it in their items.
    func themePath(for media: MediaItem) async -> String?

    /// Streamable audio of a theme path, nil when the provider has no theme music.
    func themeMusicURL(path: String) -> URL?
}

extension MediaArtworkService {
    func themePath(for media: MediaItem) async -> String? {
        media.themePath
    }

    func themeMusicURL(path _: String) -> URL? {
        nil
    }
}

@MainActor
protocol MediaDetailService: AnyObject {
    var supportsWatchlist: Bool { get }
    var supportsRemoteSubtitleSearch: Bool { get }
    var supportsAdvancedSubtitleSearch: Bool { get }
    func mediaItem(id: String) async throws -> MediaItem
    func libraryID(for media: MediaItem) async throws -> String?
    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?,
    ) async throws -> [RemoteSubtitleResult]
    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws
    func details(for media: MediaItem) async throws -> MediaDetailContent
    func fileInfo(for media: MediaItem) async throws -> MediaFileInfo?
    func fetchExtras(for media: MediaItem) async throws -> [MediaItem]
    /// The title's other editions in the same library, excluding `media` itself.
    func otherEditions(of media: MediaItem) async throws -> [MediaItem]
    func seasons(for series: MediaItem) async throws -> [MediaItem]
    func episodes(for season: MediaItem, seriesID: String?) async throws -> [MediaItem]
    func allEpisodes(for series: MediaItem) async throws -> [MediaItem]
    func setPlayed(_ played: Bool, itemID: String) async throws
    func isWatchlisted(_ media: MediaItem) async throws -> Bool
    func setWatchlisted(_ watchlisted: Bool, media: MediaItem) async throws
    /// A nil `versionID` returns the tracks of the provider's default version.
    func trackSelection(itemID: String, versionID: String?) async throws -> MediaTrackSelection
    func selectAudioTrack(id: Int, itemID: String, versionID: String?) async throws
    func selectSubtitleTrack(id: Int?, itemID: String, versionID: String?) async throws
    func collectionItems(id: String) async throws -> [MediaDisplayItem]
    func person(id: String) async throws -> Person
    func personMedia(id: String) async throws -> [MediaDisplayItem]
}

extension MediaDetailService {
    func otherEditions(of _: MediaItem) async throws -> [MediaItem] {
        []
    }
}

@MainActor
protocol MediaFavoritesService: AnyObject {
    var supportsFavorites: Bool { get }
    func favorites() async throws -> [MediaItem]
    func isFavorite(_ media: MediaItem) async throws -> Bool
    func setFavorite(_ favorite: Bool, media: MediaItem) async throws
}

@MainActor
protocol MediaPlaylistService: AnyObject {
    func playlistEntries(id: String) async throws -> [PlaylistEntry]
    /// False for Plex smart playlists and for Jellyfin playlists another user owns.
    func canEdit(_ playlist: PlaylistMediaItem) async throws -> Bool
    /// Video playlists the current user can add to.
    func editablePlaylists() async throws -> [PlaylistMediaItem]
    func createPlaylist(title: String, itemID: String) async throws
    /// Adding a media the playlist already holds succeeds without adding it twice.
    func add(itemID: String, toPlaylist playlistID: String) async throws
    func remove(_ entry: PlaylistEntry, fromPlaylist playlistID: String) async throws
    func move(_ move: PlaylistEntryMove, inPlaylist playlistID: String) async throws
    func rename(playlistID: String, to title: String) async throws
    func delete(playlistID: String) async throws
}

@MainActor
protocol MediaPlaybackService: AnyObject {
    var serverAccessGeneration: Int { get }
    func queue(startingWith itemID: String, kind: MediaKind, shuffle: Bool) async throws -> PlaybackQueue
    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue
    /// The whole playlist in its order, starting at `entry`.
    func queue(playlistID: String, startingWith entry: PlaylistEntry) async throws -> PlaybackQueue
    func prepare(
        media: MediaItem,
        resume: Bool,
        quality: TranscodeQualityPreset,
        trackPreference: MediaTrackPreference?,
        version: MediaVersionRequest,
    ) async throws -> PlaybackPlan
    func release(plan: PlaybackPlan) async
    /// Direct-play URL of the original file, carrying the token for players that cannot send headers.
    func externalPlaybackTarget(
        for media: MediaItem,
        version: MediaVersionRequest,
    ) async throws -> ExternalPlaybackTarget
    func reportStarted(
        plan: PlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws
    func reportProgress(
        plan: PlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
        currentSelection: PlaybackStreamSelection?,
    ) async throws
    func reportStopped(
        plan: PlaybackPlan,
        position: TimeInterval,
        currentSelection: PlaybackStreamSelection?,
    ) async throws
    func externalSubtitles(media: MediaItem) async throws -> [PlayerExternalSubtitle]
    /// Live progress report without a playback plan, used when playing a downloaded file.
    func reportItemPlayback(
        itemID: String,
        state: ItemPlaybackReportState,
        position: TimeInterval,
        duration: TimeInterval?,
        isPaused: Bool,
    ) async throws
    /// Deferred position push that keeps the original event date when the server supports it.
    func pushItemPosition(itemID: String, position: TimeInterval, duration: TimeInterval?, at date: Date) async throws
    func markItemWatched(itemID: String, at date: Date) async throws
    func serverWatchState(itemID: String) async throws -> ServerItemWatchState
    func serverAccessRecoveryError(from error: Error) -> MediaServerAccessRecoveryError?
    func recoverServerAccessIfUnauthorized() async throws -> Bool
    func forceServerAccessRecovery() async throws
}

@MainActor
protocol LiveTVPlaybackSession: AnyObject {
    var channel: LiveTVChannel { get }
    var backgroundPolicy: LiveTVBackgroundPolicy { get }
    var captureRange: LiveTVCaptureRange? { get }
    func source(offsetFromCaptureStart: TimeInterval?) async throws -> LiveTVPlaybackSource
    func report(position: TimeInterval, isPaused: Bool) async throws -> LiveTVCaptureRange?
    func recover() async throws -> any LiveTVPlaybackSession
    func stop() async
}

@MainActor
protocol MediaDVRService: AnyObject {
    var supportsCompletedRecordings: Bool { get }
    var canManageRecordings: Bool { get }
    var canDeleteRecordings: Bool { get }
    func upcomingRecordings() async throws -> [DVRRecording]
    func recordingRules() async throws -> [DVRRecordingRule]
    func completedRecordings() async throws -> [DVRRecording]
    func recordingTemplate(for program: LiveTVProgram) async throws -> DVRRecordingTemplate
    func schedule(_ request: DVRRecordingRequest) async throws
    func update(rule: DVRRecordingRule, options: [String: String]) async throws
    func cancel(recordingID: String) async throws
    func delete(ruleID: String) async throws
    func deleteCompleted(recordingID: String) async throws
    func reloadGuide() async throws
}

@MainActor
protocol MediaLiveTVService: AnyObject {
    var dvr: (any MediaDVRService)? { get }
    var supportsServerCaptureBuffer: Bool { get }
    func isAvailable() async throws -> Bool
    func channels() async throws -> [LiveTVChannel]
    func programs(from: Date, to: Date) async throws -> [LiveTVProgram]
    func onNow() async throws -> [LiveTVOnNowSection]
    func setFavorite(_ favorite: Bool, channel: LiveTVChannel) async throws
    func reorderFavorites(_ channels: [LiveTVChannel]) async throws
    func startPlayback(channel: LiveTVChannel) async throws -> any LiveTVPlaybackSession
}

@MainActor
protocol MediaDownloadService: AnyObject {
    func prepareDownload(
        itemID: String,
        quality: TranscodeQualityPreset,
        tracks: MediaTrackPreference,
        version: MediaVersionRequest,
    ) async throws -> MediaDownloadPreparation
    func refreshDownloadPreparation(
        _ reference: MediaDownloadRemoteReference,
    ) async throws -> MediaDownloadPreparationUpdate
    func downloadSidecars(
        itemID: String,
        tracks: MediaTrackPreference,
        versionID: String?,
    ) async throws -> [MediaDownloadSidecar]
    func cancelDownloadPreparation(_ reference: MediaDownloadRemoteReference) async
    func downloadableItems(itemID: String, kind: MediaKind) async throws -> [MediaItem]
}
