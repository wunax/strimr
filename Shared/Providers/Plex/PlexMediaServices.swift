import AetherEngine
import Foundation

@MainActor
final class PlexMediaServiceAdapter: MediaHomeService, MediaLibraryService, MediaSearchService,
    MediaArtworkService, MediaDetailService, MediaPlaybackService, MediaDownloadService,
    PlexAdvancedLibraryService, MediaAuthorizationService
{
    private let context: PlexAPIContext
    private weak var sessionManager: SessionManager?
    private let server: ServerIdentity
    private let playbackSessionID = UUID().uuidString
    private var queueItemIDs: [String: Int] = [:]
    private var subtitleResults: [String: PlexSubtitleSearchResult] = [:]
    weak var services: MediaServices?

    init(context: PlexAPIContext, sessionManager: SessionManager?, server: ServerIdentity) {
        self.context = context
        self.sessionManager = sessionManager
        self.server = server
    }

    var supportsWatchlist: Bool {
        true
    }

    var supportsRemoteSubtitleSearch: Bool {
        true
    }

    var supportsAdvancedSubtitleSearch: Bool {
        true
    }

    var serverAccessGeneration: Int {
        context.serverAccessGeneration
    }

    var authorization: MediaAuthorization {
        .plex
    }

    func serverAccessRecoveryError(from error: Error) -> MediaServerAccessRecoveryError? {
        guard let error = error as? PlexServerAccessRecoveryError else { return nil }
        switch error {
        case .accountUnauthorized:
            return .accountUnauthorized
        case .serverUnavailable:
            return .serverUnavailable
        case .connectionFailed:
            return .connectionFailed
        }
    }

    func recoverServerAccessIfUnauthorized() async throws -> Bool {
        do {
            return try await context.validateCurrentServerAccess()
        } catch {
            throw serverAccessRecoveryError(from: error) ?? error
        }
    }

    func forceServerAccessRecovery() async throws {
        do {
            try await context.forceRefreshCurrentServerAccess()
        } catch {
            throw serverAccessRecoveryError(from: error) ?? error
        }
    }

    func items(in hub: Hub, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        guard let endpoint = PlexEndpoint(key: hub.key) else { throw PlexAPIError.invalidURL }
        let response = try await HubRepository(context: context).getHubItems(
            path: endpoint.path,
            queryItems: endpoint.queryItems.filter { $0.name != "count" },
            pagination: PlexPagination(start: startIndex, size: limit),
        )
        return MediaPage(
            items: (response.mediaContainer.metadata ?? [])
                .filter(\.type.isSupported)
                .compactMap(mapDisplayItem),
            startIndex: startIndex,
            totalCount: response.mediaContainer.totalSize ?? response.mediaContainer.size,
        )
    }

    func mediaItem(id: String) async throws -> MediaItem {
        let response = try await MetadataRepository(context: context).getMetadata(ratingKey: id)
        guard let item = response.mediaContainer.metadata?.first else { throw PlexAPIError.invalidResponse }
        return MediaItem(plexItem: item, server: server)
    }

    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?,
    ) async throws -> [RemoteSubtitleResult] {
        let values = try await SubtitleRepository(context: context).search(
            ratingKey: itemID,
            language: language,
            hearingImpaired: hearingImpaired,
            forced: forced,
            title: title,
        )
        return values.map { value in
            let id = "plex.\(value.id)"
            subtitleResults[id] = value
            return RemoteSubtitleResult(
                id: id,
                title: value.title ?? value.extendedDisplayTitle ?? value.displayTitle,
                language: value.language,
                codec: value.codec,
                providerTitle: value.providerTitle,
            )
        }
    }

    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws {
        guard let value = subtitleResults[result.id] else { throw PlexAPIError.invalidResponse }
        try await SubtitleRepository(context: context).attach(
            ratingKey: itemID,
            result: value,
            searchedLanguage: result.language ?? "",
            searchedHearingImpaired: false,
            searchedForced: false,
        )
    }

    func loadHome(hiddenLibraryIDs: Set<String>, includesPlaylists: Bool) async throws -> HomeContent {
        let repository = try HubRepository(context: context)
        let sections = try await SectionRepository(context: context).getSections().mediaContainer.directory ?? []
        let visibleSectionIDs = sections
            .filter { !hiddenLibraryIDs.contains($0.key) }
            .compactMap { Int($0.key) }
        let params = hiddenLibraryIDs.isEmpty ? nil : HubRepository.HubParams(sectionIds: visibleSectionIDs)
        async let continueResponse = repository.getContinueWatchingHub(params: params)
        async let promotedResponse = repository.getPromotedHub(
            params: params,
            includeLibraryPlaylists: includesPlaylists,
        )
        let continueHub = try await continueResponse.mediaContainer.hub?.first.map(Hub.init)
        let promoted = try await promotedResponse.mediaContainer.hub ?? []
        return HomeContent(
            continueWatching: continueHub,
            recentlyAdded: promoted
                .filter { $0.hubIdentifier.lowercased().contains("recentlyadded") && $0.size > 0 }
                .map(Hub.init),
        )
    }

    func libraries() async throws -> [Library] {
        let sections = try await SectionRepository(context: context).getSections().mediaContainer.directory ?? []
        return sections.filter(\.type.isSupported).map(Library.init)
    }

    func randomArtwork(for library: Library) async throws -> ArtworkResource? {
        guard let sectionID = library.sectionId else { return nil }
        let response = try await SectionRepository(context: context).getSectionsItems(
            sectionId: sectionID,
            params: .init(sort: "random", limit: 1),
            pagination: PlexPagination(start: 0, size: 1),
        )
        guard let item = response.mediaContainer.metadata?.first,
              let path = item.art ?? item.thumb
        else { return nil }
        return try await artwork(path: path, width: 800, height: 450)
    }

    func recommended(in library: Library) async throws -> [Hub] {
        guard let sectionID = library.sectionId else { return [] }
        let response = try await HubRepository(context: context).getSectionHubs(sectionId: sectionID)
        return (response.mediaContainer.hub ?? []).map(Hub.init)
    }

    func items(
        in library: Library,
        parentID _: String?,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem> {
        guard let sectionID = library.sectionId else {
            throw PlexAPIError.missingConnection
        }
        let response = try await SectionRepository(context: context).getSectionsItems(
            sectionId: sectionID,
            params: .init(type: library.type == .series ? "2" : "1"),
            pagination: PlexPagination(start: startIndex, size: limit),
        )
        let items = (response.mediaContainer.metadata ?? []).compactMap(mapDisplayItem)
        return MediaPage(
            items: items,
            startIndex: startIndex,
            totalCount: response.mediaContainer.totalSize,
        )
    }

    func collections(in library: Library) async throws -> [CollectionMediaItem] {
        guard let sectionID = library.sectionId else { return [] }
        let response = try await SectionRepository(context: context).getSectionCollections(sectionId: sectionID)
        return (response.mediaContainer.metadata ?? []).map(CollectionMediaItem.init)
    }

    func playlists(in library: Library) async throws -> [PlaylistMediaItem] {
        guard let sectionID = library.sectionId else { return [] }
        let response = try await PlaylistRepository(context: context).getPlaylists(sectionId: sectionID)
        return (response.mediaContainer.metadata ?? []).map(PlaylistMediaItem.init)
    }

    func advancedBrowse(
        path: String,
        queryItems: [URLQueryItem],
        startIndex: Int,
        limit: Int,
    ) async throws -> PlexAdvancedBrowsePage {
        let response = try await SectionRepository(context: context).getSectionBrowseItems(
            path: path,
            queryItems: queryItems,
            pagination: PlexPagination(start: startIndex, size: limit),
        )
        let items = (response.mediaContainer.metadata ?? []).compactMap(mapBrowseItem)
        return PlexAdvancedBrowsePage(
            items: items,
            totalCount: response.mediaContainer.totalSize ?? (startIndex + items.count),
            meta: response.mediaContainer.meta,
        )
    }

    func filterOptions(path: String, queryItems: [URLQueryItem]) async throws -> [PlexFilterDirectory] {
        try await SectionRepository(context: context).getFilterOptions(path: path, queryItems: queryItems)
            .mediaContainer.directory ?? []
    }

    func sectionCharacters(
        path: String,
        queryItems: [URLQueryItem],
    ) async throws -> [PlexAdvancedSectionCharacter] {
        try await SectionRepository(context: context).getSectionFirstCharacters(path: path, queryItems: queryItems)
            .mediaContainer.directory?.compactMap { directory in
                guard let size = directory.size, size > 0 else { return nil }
                return PlexAdvancedSectionCharacter(
                    title: directory.title ?? directory.key ?? "#",
                    size: size,
                )
            } ?? []
    }

    func collectionCharacters(sectionID: Int) async throws -> [PlexAdvancedSectionCharacter] {
        try await SectionRepository(context: context).getSectionFirstCharacters(
            sectionId: sectionID,
            type: 18,
            includeCollections: true,
        ).mediaContainer.directory?.compactMap { directory in
            guard let size = directory.size, size > 0 else { return nil }
            return PlexAdvancedSectionCharacter(
                title: directory.title ?? directory.key ?? "#",
                size: size,
            )
        } ?? []
    }

    func collectionPage(sectionID: Int, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem> {
        let response = try await SectionRepository(context: context).getSectionCollections(
            sectionId: sectionID,
            includeCollections: true,
            pagination: PlexPagination(start: startIndex, size: limit),
        )
        return MediaPage(
            items: (response.mediaContainer.metadata ?? []).compactMap(mapDisplayItem),
            startIndex: startIndex,
            totalCount: response.mediaContainer.totalSize,
        )
    }

    func search(
        query: String,
        kinds: Set<MediaKind>,
        searchesAllServers: Bool,
    ) async throws -> [MediaSearchSource] {
        if searchesAllServers, let sessionManager {
            let servers = try await sessionManager.refreshAvailableServers()
            var values: [MediaSearchSource] = []
            for resource in servers {
                let childContext = try await sessionManager.serverContext(for: resource.clientIdentifier)
                guard let childServices = PlexMediaServicesFactory.make(
                    context: childContext,
                    sessionManager: sessionManager,
                ) else { continue }
                try await values.append(contentsOf: Self.search(
                    query: query,
                    kinds: kinds,
                    context: childContext,
                    serverID: resource.clientIdentifier,
                    serverName: resource.name,
                    services: childServices,
                ))
            }
            return values
        }
        guard let services else { return [] }
        let snapshot = try context.serverAccessSnapshot()
        return try await Self.search(
            query: query,
            kinds: kinds,
            context: context,
            serverID: snapshot.serverIdentifier,
            serverName: snapshot.serverIdentifier,
            services: services,
        )
    }

    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?,
    ) async throws -> ArtworkResource? {
        try await artwork(
            path: kind == .thumb ? media.preferredThumbPath : media.preferredArtPath,
            width: width,
            height: height,
        )
    }

    func artworkURL(path: String?, width: Int?, height: Int?) -> URL? {
        guard let path, let repository = try? ImageRepository(context: context) else { return nil }
        return repository.transcodeImageURL(
            path: path,
            width: width ?? 240,
            height: height ?? 360,
        )
    }

    func artwork(path: String?, width: Int?, height: Int?) async throws -> ArtworkResource? {
        artworkURL(path: path, width: width, height: height).map(ArtworkResource.url)
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        let metadataRepository = try MetadataRepository(context: context)
        let response = try await metadataRepository.getMetadata(
            ratingKey: media.id,
            params: .init(includeOnDeck: true),
        )
        let plexItem = response.mediaContainer.metadata?.first
        let mapped = plexItem.map(mapMediaItem) ?? media
        let seasons: [MediaItem]
        let episodes: [MediaItem]
        switch mapped.type {
        case .series:
            seasons = try await metadataRepository.getMetadataChildren(ratingKey: mapped.id)
                .mediaContainer.metadata?.map(mapMediaItem) ?? []
            episodes = []
        case .season:
            seasons = []
            episodes = try await metadataRepository.getMetadataChildren(ratingKey: mapped.id)
                .mediaContainer.metadata?.map(mapMediaItem) ?? []
        default:
            seasons = []
            episodes = []
        }
        let related = try await HubRepository(context: context).getRelatedMediaHubs(ratingKey: mapped.id)
        let cast = plexItem?.roles?.map {
            CastMember(
                id: "\($0.id ?? 0)-\($0.tag)",
                personID: $0.id.map(String.init),
                name: $0.tag,
                character: $0.role,
                thumbPath: $0.thumb,
            )
        } ?? []
        return try await MediaDetailContent(
            media: mapped,
            parentSeries: parentSeries(for: mapped),
            onDeck: plexItem?.onDeck?.metadata.map(mapMediaItem),
            seasons: seasons,
            episodes: episodes,
            cast: cast,
            relatedHubs: (related.mediaContainer.hub ?? []).map(Hub.init),
        )
    }

    func seasons(for series: MediaItem) async throws -> [MediaItem] {
        try await MetadataRepository(context: context).getMetadataChildren(ratingKey: series.id)
            .mediaContainer.metadata?.map(mapMediaItem) ?? []
    }

    func episodes(for season: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
        try await MetadataRepository(context: context).getMetadataChildren(ratingKey: season.id)
            .mediaContainer.metadata?.map(mapMediaItem) ?? []
    }

    func allEpisodes(for series: MediaItem) async throws -> [MediaItem] {
        try await MetadataRepository(context: context).getMetadataGrandChildren(ratingKey: series.id)
            .mediaContainer.metadata?.map(mapMediaItem).filter { $0.type == .episode } ?? []
    }

    func setPlayed(_ played: Bool, itemID: String) async throws {
        let repository = try ScrobbleRepository(context: context)
        if played {
            try await repository.markWatched(key: itemID)
        } else {
            try await repository.markUnwatched(key: itemID)
        }
    }

    func isWatchlisted(_ media: MediaItem) async throws -> Bool {
        guard let discoverID = media.plexGuidID else { return false }
        let response = try await DiscoverWatchlistRepository(context: context).getUserState(discoverID: discoverID)
        return response.mediaContainer.userState?.first?.watchlistedAt != nil
    }

    func setWatchlisted(_ watchlisted: Bool, media: MediaItem) async throws {
        guard let discoverID = media.plexGuidID else { return }
        let repository = try DiscoverWatchlistRepository(context: context)
        if watchlisted {
            try await repository.addToWatchlist(ratingKey: discoverID)
        } else {
            try await repository.removeFromWatchlist(ratingKey: discoverID)
        }
    }

    func trackSelection(itemID: String) async throws -> MediaTrackSelection {
        let response = try await MetadataRepository(context: context).getMetadata(
            ratingKey: itemID,
            params: .init(checkFiles: true),
        )
        let part = response.mediaContainer.metadata?.first?.media?.first?.parts.first
        let streams = part?.stream ?? []
        let audioTracks = streams.filter { $0.streamType == .audio }.compactMap(MediaTrackMetadata.init)
        let subtitleTracks = streams.filter { $0.streamType == .subtitle }.compactMap(MediaTrackMetadata.init)
        return MediaTrackSelection(
            itemID: itemID,
            filePath: part?.file,
            audioTracks: audioTracks,
            subtitleTracks: subtitleTracks,
            selectedAudioTrackID: audioTracks.first(where: \.isDefault)?.id ?? audioTracks.first?.id,
            selectedSubtitleTrackID: subtitleTracks.first(where: \.isDefault)?.id,
        )
    }

    func selectAudioTrack(id: Int, itemID: String) async throws {
        let partID = try await mediaPartID(itemID: itemID)
        try await PlaybackRepository(context: context).setPreferredStreams(partId: partID, audioStreamId: id)
    }

    func selectSubtitleTrack(id: Int?, itemID: String) async throws {
        let partID = try await mediaPartID(itemID: itemID)
        try await PlaybackRepository(context: context).setPreferredSubtitleStream(
            partId: partID,
            subtitleStreamId: id,
        )
    }

    func collectionItems(id: String) async throws -> [MediaDisplayItem] {
        let response = try await CollectionRepository(context: context).getCollectionChildren(ratingKey: id)
        return (response.mediaContainer.metadata ?? []).compactMap(mapDisplayItem)
    }

    func playlistItems(id: String) async throws -> [MediaDisplayItem] {
        let response = try await PlaylistRepository(context: context).getPlaylistItems(ratingKey: id)
        return (response.mediaContainer.metadata ?? []).compactMap(mapDisplayItem)
    }

    func person(id: String) async throws -> Person {
        let response = try await PersonRepository(context: context).getPerson(id: id)
        guard let value = response.mediaContainer.directory?.first else {
            throw PlexAPIError.invalidResponse
        }
        return Person(directory: value)
    }

    func personMedia(id: String) async throws -> [MediaDisplayItem] {
        let response = try await PersonRepository(context: context).getMedia(id: id)
        return (response.mediaContainer.metadata ?? []).compactMap(mapDisplayItem)
    }

    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
        let response = try await PlayQueueRepository(context: context).createQueue(
            for: media.id,
            itemType: media.type.plexType,
            shuffle: shuffle,
            continuous: media.kind == .episode || media.kind == .series || media.kind == .season,
        )
        let queueItems = response.mediaContainer.metadata ?? []
        queueItemIDs = Dictionary(uniqueKeysWithValues: queueItems.compactMap { item in
            item.playQueueItemID.map { (item.ratingKey, $0) }
        })
        let items = queueItems.map {
            PlaybackQueueItem(
                id: UUID(),
                media: MediaItem(plexItem: $0, server: server),
                providerQueueItemID: $0.playQueueItemID.map(String.init),
            )
        }
        let selectedRatingKey = response.mediaContainer.playQueueSelectedMetadataItemID
            ?? queueItems.first(where: {
                $0.playQueueItemID == response.mediaContainer.playQueueSelectedItemID
            })?.ratingKey
        return PlaybackQueue(
            id: UUID(),
            items: items,
            currentIndex: items.firstIndex(where: { $0.media.id == selectedRatingKey }) ?? 0,
            isShuffled: shuffle,
        )
    }

    func queue(startingWith itemID: String, kind _: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
        let response = try await MetadataRepository(context: context).getMetadata(ratingKey: itemID)
        guard let item = response.mediaContainer.metadata?.first else {
            throw PlexAPIError.invalidResponse
        }
        return try await queue(startingWith: MediaItem(plexItem: item, server: server), shuffle: shuffle)
    }

    func prepare(media: MediaItem, resume: Bool) async throws -> PlaybackPlan {
        let response = try await MetadataRepository(context: context).getMetadata(
            ratingKey: media.id,
            params: .init(checkFiles: true, includeChapters: true, includeMarkers: true),
        )
        guard let item = response.mediaContainer.metadata?.first,
              let part = item.media?.first?.parts.first,
              let url = try MediaRepository(context: context).mediaURL(path: part.key)
        else { throw PlexAPIError.invalidURL }
        let streams = item.media?.first?.parts.first?.stream ?? []
        let tracks = streams.compactMap { stream -> PlaybackTrack? in
            let kind: PlaybackTrackKind
            switch stream.streamType {
            case .audio: kind = .audio
            case .subtitle: kind = .subtitle
            case .video: return nil
            }
            guard let index = stream.index else { return nil }
            return PlaybackTrack(
                id: stream.id.map(String.init) ?? "plex.\(index)",
                sourceIndex: index,
                kind: kind,
                isExternal: stream.key != nil,
                title: stream.displayTitle,
                language: stream.language,
                codec: stream.codec,
                isDefault: stream.selected == true,
                isForced: stream.forced == true,
                isHearingImpaired: stream.hearingImpaired == true,
            )
        }
        let subtitles = streams.compactMap { stream -> ExternalSubtitleTrack? in
            guard stream.streamType == .subtitle,
                  stream.key != nil,
                  let url = stream.key.flatMap({ try? MediaRepository(context: context).mediaURL(path: $0) })
            else { return nil }
            return ExternalSubtitleTrack(
                url: url,
                name: stream.title ?? stream.displayTitle,
                language: stream.language,
                isForced: stream.forced == true,
                isHearingImpaired: stream.hearingImpaired == true,
                formatHint: stream.codec,
            )
        }
        let initialPosition = resume ? item.viewOffset.map { TimeInterval($0) / 1000 } : nil
        let selectedAudioIndex = streams.first {
            $0.streamType == .audio && $0.selected == true
        }?.index
        let selectedSubtitleIndex = streams.first {
            $0.streamType == .subtitle && $0.selected == true
        }?.id
        let sourceChapters = (item.chapters ?? []).filter(\.isValid)
        let chapters = sourceChapters.enumerated().map { _, chapter in
            MediaChapter(
                id: chapter.stableID,
                title: "",
                index: chapter.index,
                startTime: chapter.startTime,
                endTime: chapter.endTime,
                image: nil,
                thumbPath: chapter.thumb,
            )
        }
        return PlaybackPlan(
            media: MediaItem(plexItem: item, server: server),
            url: url,
            httpHeaders: [:],
            method: .directPlay,
            mediaSourceID: nil,
            playSessionID: playbackSessionID,
            initialPosition: initialPosition,
            selectedAudioIndex: selectedAudioIndex,
            selectedSubtitleIndex: selectedSubtitleIndex,
            tracks: tracks,
            externalSubtitles: subtitles,
            chapters: chapters,
            skipSegments: (item.markers ?? []).map {
                SkipSegment(
                    id: String($0.id),
                    kind: $0.isIntro ? .intro : .credits,
                    startTime: $0.startTime,
                    endTime: $0.endTime,
                )
            },
            scrubThumbnailSource: PlexBIFSource(partID: part.id, context: context)
                .map(ScrubThumbnailSource.plex),
        )
    }

    func reportStarted(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        try await report(plan: plan, position: position, state: isPaused ? .paused : .playing)
    }

    func reportProgress(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        try await report(plan: plan, position: position, state: isPaused ? .paused : .playing)
    }

    func reportStopped(plan: PlaybackPlan, position: TimeInterval) async throws {
        try await report(plan: plan, position: position, state: .stopped)
    }

    func externalSubtitles(media: MediaItem) async throws -> [ExternalSubtitleTrack] {
        try await prepare(media: media, resume: false).externalSubtitles
    }

    func prepareDownload(itemID: String) async throws -> MediaDownloadPreparation {
        let response = try await MetadataRepository(context: context).getMetadata(
            ratingKey: itemID,
            params: .init(checkFiles: true),
        )
        guard let item = response.mediaContainer.metadata?.first,
              let path = item.media?.first?.parts.first?.key,
              let url = try MediaRepository(context: context).mediaURL(path: path)
        else { throw PlexAPIError.invalidURL }
        return MediaDownloadPreparation(
            media: MediaItem(plexItem: item, server: server),
            request: URLRequest(url: url),
        )
    }

    func downloadableItems(itemID: String, kind: MediaKind) async throws -> [MediaItem] {
        switch kind {
        case .movie, .episode:
            return try await [prepareDownload(itemID: itemID).media]
        case .season:
            let response = try await MetadataRepository(context: context)
                .getMetadataChildren(ratingKey: itemID)
            return (response.mediaContainer.metadata ?? [])
                .filter { $0.type == .episode }
                .map(mapMediaItem)
        case .series:
            let response = try await MetadataRepository(context: context)
                .getMetadataChildren(ratingKey: itemID)
            var items: [MediaItem] = []
            for season in (response.mediaContainer.metadata ?? []).filter({ $0.type == .season }) {
                try await items.append(contentsOf: downloadableItems(itemID: season.ratingKey, kind: .season))
            }
            return items
        case .collection, .playlist, .folder, .unknown:
            return []
        }
    }

    private func report(
        plan: PlaybackPlan,
        position: TimeInterval,
        state: PlaybackRepository.PlaybackState,
    ) async throws {
        _ = try await PlaybackRepository(context: context).updateTimeline(
            ratingKey: plan.media.id,
            state: state,
            time: max(0, Int(position * 1000)),
            duration: max(0, Int((plan.media.duration ?? 0) * 1000)),
            sessionIdentifier: playbackSessionID,
            playQueueItemID: queueItemIDs[plan.media.id],
        )
    }

    private func parentSeries(for media: MediaItem) async throws -> MediaItem? {
        let seriesID: String?
        switch media.type {
        case .season:
            seriesID = media.parentRatingKey
        case .episode:
            if let grandparentRatingKey = media.grandparentRatingKey {
                seriesID = grandparentRatingKey
            } else if let seasonID = media.parentRatingKey {
                let season = try await MetadataRepository(context: context).getMetadata(ratingKey: seasonID)
                    .mediaContainer.metadata?.first
                seriesID = season?.parentRatingKey
            } else {
                seriesID = nil
            }
        case .movie, .series, .collection, .playlist, .folder, .unknown:
            seriesID = nil
        }
        guard let seriesID else { return nil }
        return try await mediaItem(id: seriesID)
    }

    private func mediaPartID(itemID: String) async throws -> Int {
        let response = try await MetadataRepository(context: context).getMetadata(
            ratingKey: itemID,
            params: .init(checkFiles: true),
        )
        guard let partID = response.mediaContainer.metadata?.first?.media?.first?.parts.first?.id else {
            throw PlexAPIError.invalidResponse
        }
        return partID
    }

    private func mapMediaItem(_ item: PlexItem) -> MediaItem {
        MediaItem(plexItem: item, server: server)
    }

    private func mapDisplayItem(_ item: PlexItem) -> MediaDisplayItem? {
        MediaDisplayItem(plexItem: item, server: server)
    }

    private func mapBrowseItem(_ metadata: PlexBrowseMetadata) -> LibraryBrowseItem? {
        switch metadata {
        case let .item(item):
            mapDisplayItem(item).map(LibraryBrowseItem.media)
        case let .folder(folder):
            .folder(LibraryBrowseFolderItem(id: folder.key, key: folder.key, title: folder.title))
        }
    }

    private static func search(
        query: String,
        kinds: Set<MediaKind>,
        context: PlexAPIContext,
        serverID: String,
        serverName: String,
        services: MediaServices,
    ) async throws -> [MediaSearchSource] {
        let types: [SearchRepository.SearchType] = if kinds == [.movie] {
            [.movies]
        } else if kinds.isEmpty {
            [.movies, .tv]
        } else {
            [.tv]
        }
        let response = try await SearchRepository(context: context).search(
            params: .init(query: query, searchTypes: types, limit: 100),
        )
        return (response.mediaContainer.searchResult ?? []).compactMap(\.metadata)
            .compactMap { MediaDisplayItem(plexItem: $0, server: services.identity) }
            .filter { kinds.isEmpty || kinds.contains($0.playableItem?.kind ?? .unknown) }
            .map {
                MediaSearchSource(
                    serverIdentifier: serverID,
                    serverName: serverName,
                    media: $0,
                    services: services,
                )
            }
    }
}

@MainActor
enum PlexMediaServicesFactory {
    static func make(context: PlexAPIContext, sessionManager: SessionManager?) -> MediaServices? {
        guard let snapshot = try? context.serverAccessSnapshot() else { return nil }
        let identity = ServerIdentity(provider: .plex, id: snapshot.serverIdentifier)
        let adapter = PlexMediaServiceAdapter(
            context: context,
            sessionManager: sessionManager,
            server: identity,
        )
        let services = MediaServices(
            provider: .plex,
            identity: identity,
            capabilities: .plex,
            home: adapter,
            library: adapter,
            search: adapter,
            artwork: adapter,
            detail: adapter,
            playback: adapter,
            downloads: adapter,
            authorization: adapter,
        )
        adapter.services = services
        return services
    }
}
