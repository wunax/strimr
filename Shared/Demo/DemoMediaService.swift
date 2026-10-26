#if DEBUG
    import AetherEngine
    import Foundation

    enum DemoMediaError: Error {
        case notFound(String)
        case missingClip
        case unsupported
    }

    /// Every media service backed by the demo catalog. What screenshots never show does nothing or returns nothing.
    @MainActor
    final class DemoMediaService: MediaHomeService, MediaLibraryService, MediaSearchService, MediaArtworkService,
        MediaDetailService, MediaFavoritesService, MediaPlaylistService, MediaPlaybackService, MediaLiveTVService,
        MediaDownloadService, MediaAuthorizationService
    {
        private static let artworkCache: NSCache<NSString, NSData> = {
            let cache = NSCache<NSString, NSData>()
            cache.totalCostLimit = 256 * 1024 * 1024
            return cache
        }()

        private let catalog: DemoCatalog
        private let contentDirectory: URL
        private var selectedAudioTrackIDs: [String: Int] = [:]
        private var selectedSubtitleTrackIDs: [String: Int?] = [:]

        init(catalog: DemoCatalog, contentDirectory: URL) {
            self.catalog = catalog
            self.contentDirectory = contentDirectory
        }

        private func item(id: String) throws -> MediaItem {
            guard let item = catalog.item(id: id) else { throw DemoMediaError.notFound(id) }
            return item
        }

        private func page<Element>(_ items: [Element], startIndex: Int, limit: Int) -> MediaPage<Element> {
            let start = min(startIndex, items.count)
            let end = min(start + limit, items.count)
            return MediaPage(items: Array(items[start ..< end]), startIndex: start, totalCount: items.count)
        }

        // MARK: - Home

        func loadHome(
            hiddenLibraryIDs _: Set<String>,
            includesPlaylists _: Bool,
            shownRowIDs _: Set<String>,
        ) async throws -> HomeContent {
            HomeContent(rows: catalog.homeRows)
        }

        func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
            page(hub.items, startIndex: startIndex, limit: limit)
        }

        // MARK: - Library

        func libraries() async throws -> [Library] {
            catalog.libraries
        }

        func preview(for library: Library) async throws -> LibraryPreview? {
            let titles = catalog.titles(in: library.id)
            var artworks: [ArtworkResource] = []
            for title in titles.prefix(LibraryPreview.artworkCount) {
                if let artwork = try await artwork(path: title.artPath, width: nil, height: nil) {
                    artworks.append(artwork)
                }
            }
            return LibraryPreview(artworks: artworks, itemCount: titles.count)
        }

        func recommended(in library: Library) async throws -> [Hub] {
            catalog.recommendedHubs(in: library.id)
        }

        func items(
            in library: Library,
            parentID: String?,
            startIndex: Int,
            limit: Int,
        ) async throws -> MediaPage<MediaDisplayItem> {
            let items: [MediaItem] = if let parentID {
                catalog.seasons(ofSeries: parentID) + catalog.episodes(ofSeason: parentID)
            } else {
                catalog.titles(in: library.id)
            }
            return page(items.map(MediaDisplayItem.playable), startIndex: startIndex, limit: limit)
        }

        func collections(in _: Library) async throws -> [CollectionMediaItem] {
            []
        }

        func playlists(in _: Library) async throws -> [PlaylistMediaItem] {
            []
        }

        // MARK: - Search

        func search(query: String, kinds: Set<MediaKind>) async throws -> [MediaDisplayItem] {
            catalog.allTitles
                .filter { (kinds.isEmpty || kinds.contains($0.type)) && $0.title.localizedStandardContains(query) }
                .map(MediaDisplayItem.playable)
        }

        // MARK: - Artwork

        func artworkURL(path: String?, width _: Int?, height _: Int?) -> URL? {
            path.map { contentDirectory.appending(path: $0) }
        }

        func artwork(
            for media: MediaDisplayItem,
            kind: MediaImageViewModel.ArtworkKind,
            width: Int?,
            height: Int?,
        ) async throws -> ArtworkResource? {
            let path = kind == .thumb ? media.preferredThumbPath : media.preferredArtPath
            return try await artwork(path: path, width: width, height: height)
        }

        func artwork(path: String?, width: Int?, height: Int?) async throws -> ArtworkResource? {
            guard let url = artworkURL(path: path, width: width, height: height) else { return nil }
            if let cached = Self.artworkCache.object(forKey: url.path() as NSString) {
                return .data(cached as Data)
            }
            let data = try await Task.detached { try Data(contentsOf: url) }.value
            Self.artworkCache.setObject(data as NSData, forKey: url.path() as NSString, cost: data.count)
            return .data(data)
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

        func mediaItem(id: String) async throws -> MediaItem {
            try item(id: id)
        }

        func libraryID(for media: MediaItem) async throws -> String? {
            media.librarySectionID
        }

        func searchSubtitles(
            itemID _: String,
            language _: String,
            hearingImpaired _: Bool,
            forced _: Bool,
            title _: String?,
        ) async throws -> [RemoteSubtitleResult] {
            []
        }

        func installSubtitle(itemID _: String, result _: RemoteSubtitleResult) async throws {}

        func details(for media: MediaItem) async throws -> MediaDetailContent {
            let media = try item(id: media.id)
            let seriesID = media.type == .series ? nil : media.grandparentRatingKey
            return try MediaDetailContent(
                media: media,
                parentSeries: seriesID.map(item(id:)),
                onDeck: media.type == .series ? catalog.onDeck(forSeries: media.id) : nil,
                seasons: media.type == .series ? catalog.seasons(ofSeries: media.id) : [],
                episodes: media.type == .season ? catalog.episodes(ofSeason: media.id) : [],
                cast: catalog.cast(for: media),
                relatedHubs: relatedHubs(for: media),
            )
        }

        /// Titles of the same library sharing a genre, most shared genres first.
        private func relatedHubs(for media: MediaItem) -> [Hub] {
            guard media.type == .movie || media.type == .series, let libraryID = media.librarySectionID else {
                return []
            }
            let genres = Set(media.genres)
            let related = catalog.titles(in: libraryID)
                .filter { $0.id != media.id }
                .map { ($0, Set($0.genres).intersection(genres).count) }
                .sorted { $0.1 > $1.1 }
                .prefix(10)
                .map { MediaDisplayItem.playable($0.0) }
            guard !related.isEmpty else { return [] }
            return [Hub(
                id: "demo.similar.\(media.id)",
                key: "demo.similar.\(media.id)",
                hubKey: nil,
                title: String(localized: "jellyfin.detail.similar"),
                size: related.count,
                more: false,
                items: Array(related),
                server: media.identity.server,
            )]
        }

        func fileInfo(for _: MediaItem) async throws -> MediaFileInfo? {
            nil
        }

        func fetchExtras(for _: MediaItem) async throws -> [MediaItem] {
            []
        }

        func seasons(for series: MediaItem) async throws -> [MediaItem] {
            catalog.seasons(ofSeries: series.id)
        }

        func episodes(for season: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
            catalog.episodes(ofSeason: season.id)
        }

        func allEpisodes(for series: MediaItem) async throws -> [MediaItem] {
            catalog.episodes(ofSeries: series.id)
        }

        func setPlayed(_: Bool, itemID _: String) async throws {}

        func isWatchlisted(_: MediaItem) async throws -> Bool {
            false
        }

        func setWatchlisted(_: Bool, media _: MediaItem) async throws {}

        func trackSelection(itemID: String, versionID _: String?) async throws -> MediaTrackSelection {
            MediaTrackSelection(
                itemID: itemID,
                filePath: nil,
                audioTracks: Self.audioTracks,
                subtitleTracks: Self.subtitleTracks,
                selectedAudioTrackID: selectedAudioTrackIDs[itemID] ?? Self.audioTracks.first?.id,
                selectedSubtitleTrackID: selectedSubtitleTrackIDs[itemID] ?? nil,
                versions: [],
                versionID: nil,
                defaultVersionID: nil,
            )
        }

        func selectAudioTrack(id: Int, itemID: String, versionID _: String?) async throws {
            selectedAudioTrackIDs[itemID] = id
        }

        func selectSubtitleTrack(id: Int?, itemID: String, versionID _: String?) async throws {
            selectedSubtitleTrackIDs[itemID] = id
        }

        private static let audioTracks = [
            track(id: 1, codec: "truehd", language: "en", detail: "Dolby Atmos 7.1", isDefault: true),
            track(id: 2, codec: "eac3", language: "fr", detail: "Dolby Digital+ 5.1"),
        ]

        private static let subtitleTracks = [
            track(id: 3, codec: "srt", language: "en"),
            track(id: 4, codec: "srt", language: "en", detail: "SDH", isHearingImpaired: true),
            track(id: 5, codec: "srt", language: "fr"),
            track(id: 6, codec: "srt", language: "es"),
        ]

        private static func track(
            id: Int,
            codec: String,
            language: String,
            detail: String? = nil,
            isDefault: Bool = false,
            isHearingImpaired: Bool = false,
        ) -> MediaTrackMetadata {
            let name = Locale.current.localizedString(forLanguageCode: language)?.localizedCapitalized ?? language
            return MediaTrackMetadata(
                id: id,
                sourceIndex: id,
                codec: codec,
                title: detail,
                displayTitle: [name, detail].compactMap(\.self).joined(separator: " · "),
                language: language,
                isDefault: isDefault,
                isForced: false,
                isHearingImpaired: isHearingImpaired,
            )
        }

        func collectionItems(id _: String) async throws -> [MediaDisplayItem] {
            []
        }

        func person(id: String) async throws -> Person {
            guard let person = catalog.person(id: id) else { throw DemoMediaError.notFound(id) }
            return person
        }

        func personMedia(id: String) async throws -> [MediaDisplayItem] {
            catalog.titles(withPerson: id).map(MediaDisplayItem.playable)
        }

        // MARK: - Favorites

        var supportsFavorites: Bool {
            true
        }

        func favorites() async throws -> [MediaItem] {
            []
        }

        func isFavorite(_: MediaItem) async throws -> Bool {
            false
        }

        func setFavorite(_: Bool, media _: MediaItem) async throws {}

        // MARK: - Playlists

        func playlistEntries(id _: String) async throws -> [PlaylistEntry] {
            []
        }

        func canEdit(_: PlaylistMediaItem) async throws -> Bool {
            false
        }

        func editablePlaylists() async throws -> [PlaylistMediaItem] {
            []
        }

        func createPlaylist(title _: String, itemID _: String) async throws {}

        func add(itemID _: String, toPlaylist _: String) async throws {}

        func remove(_: PlaylistEntry, fromPlaylist _: String) async throws {}

        func move(_: PlaylistEntryMove, inPlaylist _: String) async throws {}

        func rename(playlistID _: String, to _: String) async throws {}

        func delete(playlistID _: String) async throws {}

        // MARK: - Playback

        var serverAccessGeneration: Int {
            0
        }

        func queue(startingWith itemID: String, kind _: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
            try await queue(startingWith: item(id: itemID), shuffle: shuffle)
        }

        func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
            let items: [MediaItem] = switch media.type {
            case .series:
                catalog.onDeck(forSeries: media.id).map { [$0] } ?? []
            case .season:
                catalog.episodes(ofSeason: media.id)
            case .episode:
                media.grandparentRatingKey.map { catalog.episodes(ofSeries: $0) } ?? [media]
            default:
                [media]
            }
            let queueItems = items.map { PlaybackQueueItem(id: UUID(), media: $0, providerQueueItemID: nil) }
            return PlaybackQueue(
                id: UUID(),
                items: queueItems,
                currentIndex: queueItems.firstIndex { $0.media.id == media.id } ?? 0,
                isShuffled: shuffle,
            )
        }

        func queue(playlistID _: String, startingWith _: PlaylistEntry) async throws -> PlaybackQueue {
            throw DemoMediaError.unsupported
        }

        func prepare(
            media: MediaItem,
            resume _: Bool,
            quality: TranscodeQualityPreset,
            trackPreference _: MediaTrackPreference?,
            version _: MediaVersionRequest,
        ) async throws -> PlaybackPlan {
            let clip = contentDirectory.appending(path: "clip.mp4")
            guard FileManager.default.fileExists(atPath: clip.path()) else { throw DemoMediaError.missingClip }
            return PlaybackPlan(
                media: media,
                url: clip,
                httpHeaders: [:],
                method: .directPlay,
                requestedQuality: quality,
                effectiveQuality: quality,
                qualityFallbackMessage: nil,
                mediaSourceID: nil,
                playSessionID: nil,
                transcodeSessionID: nil,
                initialPosition: nil,
                selectedAudioIndex: nil,
                selectedSubtitleIndex: nil,
                subtitleSelectionIsOff: true,
                tracks: [],
                externalSubtitles: [],
                chapters: [],
                skipSegments: [],
                scrubThumbnailSource: nil,
                versions: [],
                versionID: nil,
            )
        }

        func release(plan _: PlaybackPlan) async {}

        func externalPlaybackTarget(
            for _: MediaItem,
            version _: MediaVersionRequest,
        ) async throws -> ExternalPlaybackTarget {
            throw DemoMediaError.unsupported
        }

        func reportStarted(
            plan _: PlaybackPlan,
            position _: TimeInterval,
            isPaused _: Bool,
            currentSelection _: PlaybackStreamSelection?,
        ) async throws {}

        func reportProgress(
            plan _: PlaybackPlan,
            position _: TimeInterval,
            isPaused _: Bool,
            currentSelection _: PlaybackStreamSelection?,
        ) async throws {}

        func reportStopped(
            plan _: PlaybackPlan,
            position _: TimeInterval,
            currentSelection _: PlaybackStreamSelection?,
        ) async throws {}

        func externalSubtitles(media _: MediaItem) async throws -> [ExternalSubtitleTrack] {
            []
        }

        func reportItemPlayback(
            itemID _: String,
            state _: ItemPlaybackReportState,
            position _: TimeInterval,
            duration _: TimeInterval?,
            isPaused _: Bool,
        ) async throws {}

        func pushItemPosition(itemID _: String, position _: TimeInterval, duration _: TimeInterval?, at _: Date)
            async throws {}

        func markItemWatched(itemID _: String, at _: Date) async throws {}

        func serverWatchState(itemID _: String) async throws -> ServerItemWatchState {
            ServerItemWatchState(viewOffset: nil, viewCount: 0, isPlayed: false, lastViewedAt: nil)
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
            []
        }

        func programs(from _: Date, to _: Date) async throws -> [LiveTVProgram] {
            []
        }

        func onNow() async throws -> [LiveTVOnNowSection] {
            []
        }

        func setFavorite(_: Bool, channel _: LiveTVChannel) async throws {}

        func reorderFavorites(_: [LiveTVChannel]) async throws {}

        func startPlayback(channel _: LiveTVChannel) async throws -> any LiveTVPlaybackSession {
            throw DemoMediaError.unsupported
        }

        // MARK: - Downloads

        func prepareDownload(
            itemID _: String,
            quality _: TranscodeQualityPreset,
            tracks _: MediaTrackPreference,
            version _: MediaVersionRequest,
        ) async throws -> MediaDownloadPreparation {
            throw DemoMediaError.unsupported
        }

        func refreshDownloadPreparation(
            _: MediaDownloadRemoteReference,
        ) async throws -> MediaDownloadPreparationUpdate {
            throw DemoMediaError.unsupported
        }

        func downloadSidecars(
            itemID _: String,
            tracks _: MediaTrackPreference,
            versionID _: String?,
        ) async throws -> [MediaDownloadSidecar] {
            []
        }

        func cancelDownloadPreparation(_: MediaDownloadRemoteReference) async {}

        func downloadableItems(itemID _: String, kind _: MediaKind) async throws -> [MediaItem] {
            []
        }

        // MARK: - Authorization

        var authorization: MediaAuthorization {
            .denied
        }
    }

    enum DemoMediaServices {
        static let capabilities = ProviderCapabilities(
            profiles: false,
            multiServerSearch: false,
            cloudWatchlist: false,
            favorites: true,
            remoteSubtitleSearch: false,
            trickplay: false,
            skipSegments: false,
            downloads: true,
            sharePlay: false,
            topShelf: false,
            syncPlay: false,
        )

        static func make(server: ServerIdentity) throws -> MediaServices {
            let catalog = try DemoCatalog.load(server: server)
            guard let directory = DemoMode.contentDirectory else { throw DemoCatalog.LoadError.missingContentDirectory }
            let service = DemoMediaService(catalog: catalog, contentDirectory: directory)
            return MediaServices(
                provider: server.provider,
                identity: server,
                serverName: catalog.serverName,
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
#endif
