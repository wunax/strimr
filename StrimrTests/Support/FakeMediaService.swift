import AetherEngine
import Foundation
@testable import Strimr

/// Every media service at once. Throwing calls fail with `NotStubbed` so an unexpected call shows up in the test;
/// subclass it and override only what the code under test needs.
class FakeMediaService: MediaHomeService, MediaLibraryService, MediaSearchService, MediaArtworkService,
    MediaDetailService, MediaFavoritesService, MediaPlaylistService, MediaPlaybackService, MediaLiveTVService,
    MediaDownloadService, MediaAuthorizationService
{
    struct NotStubbed: Error, CustomStringConvertible {
        let function: String

        var description: String {
            "FakeMediaService.\(function) is not stubbed"
        }
    }

    // MARK: - Home

    func loadHome(
        hiddenLibraryIDs _: Set<String>,
        includesPlaylists _: Bool,
        shownRowIDs _: Set<String>,
    ) async throws -> HomeContent {
        throw NotStubbed(function: #function)
    }

    func homeRowCatalog(hiddenLibraryIDs _: Set<String>) async throws -> [HomeRow] {
        throw NotStubbed(function: #function)
    }

    func items(in _: Hub, startIndex _: Int, limit _: Int) async throws -> MediaPage<MediaDisplayItem> {
        throw NotStubbed(function: #function)
    }

    // MARK: - Library

    func libraries() async throws -> [Library] {
        throw NotStubbed(function: #function)
    }

    func preview(for _: Library) async throws -> LibraryPreview? {
        throw NotStubbed(function: #function)
    }

    func recommended(in _: Library) async throws -> [Hub] {
        throw NotStubbed(function: #function)
    }

    func items(
        in _: Library,
        parentID _: String?,
        startIndex _: Int,
        limit _: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        throw NotStubbed(function: #function)
    }

    func collections(in _: Library) async throws -> [CollectionMediaItem] {
        throw NotStubbed(function: #function)
    }

    func playlists(in _: Library) async throws -> [PlaylistMediaItem] {
        throw NotStubbed(function: #function)
    }

    // MARK: - Search

    func search(query _: String, kinds _: Set<MediaKind>) async throws -> [MediaDisplayItem] {
        throw NotStubbed(function: #function)
    }

    // MARK: - Artwork

    func artworkURL(path _: String?, width _: Int?, height _: Int?) -> URL? {
        nil
    }

    func artwork(
        for _: MediaDisplayItem,
        kind _: MediaImageViewModel.ArtworkKind,
        width _: Int?,
        height _: Int?,
    ) async throws -> ArtworkResource? {
        throw NotStubbed(function: #function)
    }

    func artwork(path _: String?, width _: Int?, height _: Int?) async throws -> ArtworkResource? {
        throw NotStubbed(function: #function)
    }

    func themeMusicURL(path _: String) -> URL? {
        nil
    }

    // MARK: - Detail

    var supportsWatchlist: Bool {
        false
    }

    var supportsRemoteSubtitleSearch: Bool {
        false
    }

    var supportsAdvancedSubtitleSearch: Bool {
        false
    }

    func mediaItem(id _: String) async throws -> MediaItem {
        throw NotStubbed(function: #function)
    }

    func libraryID(for _: MediaItem) async throws -> String? {
        throw NotStubbed(function: #function)
    }

    func searchSubtitles(
        itemID _: String,
        language _: String,
        hearingImpaired _: Bool,
        forced _: Bool,
        title _: String?,
    ) async throws -> [RemoteSubtitleResult] {
        throw NotStubbed(function: #function)
    }

    func installSubtitle(itemID _: String, result _: RemoteSubtitleResult) async throws {
        throw NotStubbed(function: #function)
    }

    func details(for _: MediaItem) async throws -> MediaDetailContent {
        throw NotStubbed(function: #function)
    }

    func fileInfo(for _: MediaItem) async throws -> MediaFileInfo? {
        throw NotStubbed(function: #function)
    }

    func fetchExtras(for _: MediaItem) async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    func seasons(for _: MediaItem) async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    func episodes(for _: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    func allEpisodes(for _: MediaItem) async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    func setPlayed(_: Bool, itemID _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func isWatchlisted(_: MediaItem) async throws -> Bool {
        throw NotStubbed(function: #function)
    }

    func setWatchlisted(_: Bool, media _: MediaItem) async throws {
        throw NotStubbed(function: #function)
    }

    func trackSelection(itemID _: String, versionID _: String?) async throws -> MediaTrackSelection {
        throw NotStubbed(function: #function)
    }

    func selectAudioTrack(id _: Int, itemID _: String, versionID _: String?) async throws {
        throw NotStubbed(function: #function)
    }

    func selectSubtitleTrack(id _: Int?, itemID _: String, versionID _: String?) async throws {
        throw NotStubbed(function: #function)
    }

    func collectionItems(id _: String) async throws -> [MediaDisplayItem] {
        throw NotStubbed(function: #function)
    }

    func person(id _: String) async throws -> Person {
        throw NotStubbed(function: #function)
    }

    func personMedia(id _: String) async throws -> [MediaDisplayItem] {
        throw NotStubbed(function: #function)
    }

    // MARK: - Favorites

    var supportsFavorites: Bool {
        false
    }

    func favorites() async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    func isFavorite(_: MediaItem) async throws -> Bool {
        throw NotStubbed(function: #function)
    }

    func setFavorite(_: Bool, media _: MediaItem) async throws {
        throw NotStubbed(function: #function)
    }

    // MARK: - Playlists

    func playlistEntries(id _: String) async throws -> [PlaylistEntry] {
        throw NotStubbed(function: #function)
    }

    func canEdit(_: PlaylistMediaItem) async throws -> Bool {
        throw NotStubbed(function: #function)
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        throw NotStubbed(function: #function)
    }

    func createPlaylist(title _: String, itemID _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func add(itemID _: String, toPlaylist _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func remove(_: PlaylistEntry, fromPlaylist _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func move(_: PlaylistEntryMove, inPlaylist _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func rename(playlistID _: String, to _: String) async throws {
        throw NotStubbed(function: #function)
    }

    func delete(playlistID _: String) async throws {
        throw NotStubbed(function: #function)
    }

    // MARK: - Playback

    var serverAccessGeneration: Int {
        0
    }

    func queue(startingWith _: String, kind _: MediaKind, shuffle _: Bool) async throws -> PlaybackQueue {
        throw NotStubbed(function: #function)
    }

    func queue(startingWith _: MediaItem, shuffle _: Bool) async throws -> PlaybackQueue {
        throw NotStubbed(function: #function)
    }

    func queue(playlistID _: String, startingWith _: PlaylistEntry) async throws -> PlaybackQueue {
        throw NotStubbed(function: #function)
    }

    func prepare(
        media _: MediaItem,
        resume _: Bool,
        quality _: TranscodeQualityPreset,
        trackPreference _: MediaTrackPreference?,
        version _: MediaVersionRequest,
    ) async throws -> PlaybackPlan {
        throw NotStubbed(function: #function)
    }

    func release(plan _: PlaybackPlan) async {}

    func externalPlaybackTarget(
        for _: MediaItem,
        version _: MediaVersionRequest,
    ) async throws -> ExternalPlaybackTarget {
        throw NotStubbed(function: #function)
    }

    func reportStarted(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        isPaused _: Bool,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {
        throw NotStubbed(function: #function)
    }

    func reportProgress(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        isPaused _: Bool,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {
        throw NotStubbed(function: #function)
    }

    func reportStopped(
        plan _: PlaybackPlan,
        position _: TimeInterval,
        currentSelection _: PlaybackStreamSelection?,
    ) async throws {
        throw NotStubbed(function: #function)
    }

    func externalSubtitles(media _: MediaItem) async throws -> [PlayerExternalSubtitle] {
        throw NotStubbed(function: #function)
    }

    func reportItemPlayback(
        itemID _: String,
        state _: ItemPlaybackReportState,
        position _: TimeInterval,
        duration _: TimeInterval?,
        isPaused _: Bool,
    ) async throws {
        throw NotStubbed(function: #function)
    }

    func pushItemPosition(itemID _: String, position _: TimeInterval, duration _: TimeInterval?, at _: Date)
        async throws
    {
        throw NotStubbed(function: #function)
    }

    func markItemWatched(itemID _: String, at _: Date) async throws {
        throw NotStubbed(function: #function)
    }

    func serverWatchState(itemID _: String) async throws -> ServerItemWatchState {
        throw NotStubbed(function: #function)
    }

    func serverAccessRecoveryError(from _: Error) -> MediaServerAccessRecoveryError? {
        nil
    }

    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        false
    }

    func forceServerAccessRecovery() async throws {}

    // MARK: - Live TV

    var dvr: (any MediaDVRService)? {
        nil
    }

    var supportsServerCaptureBuffer: Bool {
        false
    }

    func isAvailable() async throws -> Bool {
        false
    }

    func channels() async throws -> [LiveTVChannel] {
        throw NotStubbed(function: #function)
    }

    func programs(from _: Date, to _: Date) async throws -> [LiveTVProgram] {
        throw NotStubbed(function: #function)
    }

    func onNow() async throws -> [LiveTVOnNowSection] {
        throw NotStubbed(function: #function)
    }

    func setFavorite(_: Bool, channel _: LiveTVChannel) async throws {
        throw NotStubbed(function: #function)
    }

    func reorderFavorites(_: [LiveTVChannel]) async throws {
        throw NotStubbed(function: #function)
    }

    func startPlayback(channel _: LiveTVChannel) async throws -> any LiveTVPlaybackSession {
        throw NotStubbed(function: #function)
    }

    // MARK: - Downloads

    func prepareDownload(
        itemID _: String,
        quality _: TranscodeQualityPreset,
        tracks _: MediaTrackPreference,
        version _: MediaVersionRequest,
    ) async throws -> MediaDownloadPreparation {
        throw NotStubbed(function: #function)
    }

    func refreshDownloadPreparation(
        _: MediaDownloadRemoteReference,
    ) async throws -> MediaDownloadPreparationUpdate {
        throw NotStubbed(function: #function)
    }

    func downloadSidecars(
        itemID _: String,
        tracks _: MediaTrackPreference,
        versionID _: String?,
    ) async throws -> [MediaDownloadSidecar] {
        throw NotStubbed(function: #function)
    }

    func cancelDownloadPreparation(_: MediaDownloadRemoteReference) async {}

    func downloadableItems(itemID _: String, kind _: MediaKind) async throws -> [MediaItem] {
        throw NotStubbed(function: #function)
    }

    // MARK: - Authorization

    var authorization: MediaAuthorization {
        .denied
    }
}

extension MediaServices {
    static func fake(
        _ service: FakeMediaService? = nil,
        server: ServerIdentity = ServerIdentity(provider: .jellyfin, id: "server-1"),
        capabilities: ProviderCapabilities = .jellyfin,
    ) -> MediaServices {
        let service = service ?? FakeMediaService()
        return MediaServices(
            provider: server.provider,
            identity: server,
            serverName: "Test Server",
            capabilities: capabilities,
            home: service,
            library: service,
            search: service,
            artwork: service,
            detail: service,
            favorites: service,
            playlists: service,
            playback: service,
            liveTV: service,
            downloads: service,
            authorization: service,
        )
    }
}
