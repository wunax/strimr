import AetherEngine
import Foundation

@MainActor
final class PlexMediaServiceAdapter: MediaHomeService, MediaLibraryService, MediaSearchService,
    MediaArtworkService, MediaDetailService, MediaPlaybackService
{
    private let context: PlexAPIContext
    private weak var sessionManager: SessionManager?
    private let server: ServerIdentity
    private let playbackSessionID = UUID().uuidString
    private var queueItemIDs: [String: Int] = [:]
    weak var services: MediaServices?

    init(context: PlexAPIContext, sessionManager: SessionManager?, server: ServerIdentity) {
        self.context = context
        self.sessionManager = sessionManager
        self.server = server
    }

    var supportsWatchlist: Bool { true }
    var supportsRemoteSubtitleSearch: Bool { true }

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
            includeLibraryPlaylists: includesPlaylists
        )
        let continueHub = try await continueResponse.mediaContainer.hub?.first.map(Hub.init)
        let promoted = try await promotedResponse.mediaContainer.hub ?? []
        return HomeContent(
            continueWatching: continueHub,
            recentlyAdded: promoted
                .filter { $0.hubIdentifier.lowercased().contains("recentlyadded") && $0.size > 0 }
                .map(Hub.init)
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
            pagination: PlexPagination(start: 0, size: 1)
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
        limit: Int
    ) async throws -> MediaPage<MediaDisplayItem> {
        guard let sectionID = library.sectionId else {
            throw PlexAPIError.missingConnection
        }
        let response = try await SectionRepository(context: context).getSectionsItems(
            sectionId: sectionID,
            params: .init(type: library.type == .show ? "2" : "1"),
            pagination: PlexPagination(start: startIndex, size: limit)
        )
        let items = (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
        return MediaPage(
            items: items,
            startIndex: startIndex,
            totalCount: response.mediaContainer.totalSize
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

    func search(
        query: String,
        kinds: Set<MediaKind>,
        searchesAllServers: Bool
    ) async throws -> [MediaSearchSource] {
        if searchesAllServers, let sessionManager {
            let servers = try await sessionManager.refreshAvailableServers()
            var values: [MediaSearchSource] = []
            for resource in servers {
                let childContext = try await sessionManager.serverContext(for: resource.clientIdentifier)
                guard let childServices = PlexMediaServicesFactory.make(
                    context: childContext,
                    sessionManager: sessionManager
                ) else { continue }
                values.append(contentsOf: try await Self.search(
                    query: query,
                    kinds: kinds,
                    context: childContext,
                    serverID: resource.clientIdentifier,
                    serverName: resource.name,
                    services: childServices
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
            services: services
        )
    }

    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?
    ) async throws -> ArtworkResource? {
        try await artwork(
            path: kind == .thumb ? media.preferredThumbPath : media.preferredArtPath,
            width: width,
            height: height
        )
    }

    func artwork(path: String?, width: Int?, height: Int?) async throws -> ArtworkResource? {
        guard let path else { return nil }
        let repository = try ImageRepository(context: context)
        return repository.transcodeImageURL(
            path: path,
            width: width ?? 240,
            height: height ?? 360
        ).map(ArtworkResource.url)
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        let metadataRepository = try MetadataRepository(context: context)
        let response = try await metadataRepository.getMetadata(
            ratingKey: media.metadataRatingKey,
            params: .init(includeOnDeck: true)
        )
        let plexItem = response.mediaContainer.metadata?.first
        let mapped = plexItem.map(MediaItem.init) ?? media
        let seasons: [MediaItem]
        let episodes: [MediaItem]
        switch mapped.type {
        case .show:
            seasons = try await metadataRepository.getMetadataChildren(ratingKey: mapped.id)
                .mediaContainer.metadata?.map(MediaItem.init) ?? []
            episodes = []
        case .season:
            seasons = []
            episodes = try await metadataRepository.getMetadataChildren(ratingKey: mapped.id)
                .mediaContainer.metadata?.map(MediaItem.init) ?? []
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
                thumbPath: $0.thumb
            )
        } ?? []
        return MediaDetailContent(
            media: mapped,
            parentSeries: nil,
            onDeck: plexItem?.onDeck?.metadata.map(MediaItem.init),
            seasons: seasons,
            episodes: episodes,
            cast: cast,
            relatedHubs: (related.mediaContainer.hub ?? []).map(Hub.init)
        )
    }

    func seasons(for series: MediaItem) async throws -> [MediaItem] {
        try await MetadataRepository(context: context).getMetadataChildren(ratingKey: series.id)
            .mediaContainer.metadata?.map(MediaItem.init) ?? []
    }

    func episodes(for season: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
        try await MetadataRepository(context: context).getMetadataChildren(ratingKey: season.id)
            .mediaContainer.metadata?.map(MediaItem.init) ?? []
    }

    func setPlayed(_ played: Bool, itemID: String) async throws {
        let repository = try ScrobbleRepository(context: context)
        if played {
            try await repository.markWatched(key: itemID)
        } else {
            try await repository.markUnwatched(key: itemID)
        }
    }

    func collectionItems(id: String) async throws -> [MediaDisplayItem] {
        let response = try await CollectionRepository(context: context).getCollectionChildren(ratingKey: id)
        return (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
    }

    func playlistItems(id: String) async throws -> [MediaDisplayItem] {
        let response = try await PlaylistRepository(context: context).getPlaylistItems(ratingKey: id)
        return (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
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
        return (response.mediaContainer.metadata ?? []).compactMap(MediaDisplayItem.init)
    }

    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
        let manager = try PlayQueueManager(context: context)
        let state = try await manager.createQueue(
            for: media.id,
            itemType: media.type,
            continuous: media.kind == .episode || media.kind == .series || media.kind == .season,
            shuffle: shuffle
        )
        queueItemIDs = Dictionary(uniqueKeysWithValues: state.items.compactMap { item in
            item.playQueueItemID.map { (item.ratingKey, $0) }
        })
        let items = state.items.map {
            PlaybackQueueItem(
                id: UUID(),
                media: MediaItem(plexItem: $0),
                providerQueueItemID: $0.playQueueItemID.map(String.init)
            )
        }
        return PlaybackQueue(
            id: UUID(),
            items: items,
            currentIndex: items.firstIndex(where: { $0.media.id == state.selectedRatingKey }) ?? 0,
            isShuffled: shuffle
        )
    }

    func queue(startingWith itemID: String, kind: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
        let response = try await MetadataRepository(context: context).getMetadata(ratingKey: itemID)
        guard let item = response.mediaContainer.metadata?.first else {
            throw PlexAPIError.invalidResponse
        }
        return try await queue(startingWith: MediaItem(plexItem: item), shuffle: shuffle)
    }

    func prepare(media: MediaItem, resume: Bool) async throws -> PlaybackPlan {
        let response = try await MetadataRepository(context: context).getMetadata(
            ratingKey: media.id,
            params: .init(checkFiles: true, includeChapters: true, includeMarkers: true)
        )
        guard let item = response.mediaContainer.metadata?.first,
              let path = item.media?.first?.parts.first?.key,
              let url = try MediaRepository(context: context).mediaURL(path: path)
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
                title: stream.title ?? stream.displayTitle,
                language: stream.language,
                codec: stream.codec,
                isDefault: stream.selected == true,
                isForced: stream.forced == true,
                isHearingImpaired: stream.hearingImpaired == true
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
                formatHint: stream.codec
            )
        }
        let initialPosition = resume ? item.viewOffset.map { TimeInterval($0) / 1000 } : nil
        let selectedAudioIndex = streams.first {
            $0.streamType == .audio && $0.selected == true
        }?.index
        let selectedSubtitleIndex = streams.first {
            $0.streamType == .subtitle && $0.selected == true
        }?.index
        let chapters = (item.chapters ?? []).map {
            MediaChapter(
                id: String($0.index),
                title: "",
                startTime: TimeInterval($0.startTimeOffset) / 1000,
                image: nil
            )
        }
        return PlaybackPlan(
            media: MediaItem(plexItem: item),
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
            chapters: chapters
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

    private func report(
        plan: PlaybackPlan,
        position: TimeInterval,
        state: PlaybackRepository.PlaybackState
    ) async throws {
        _ = try await PlaybackRepository(context: context).updateTimeline(
            ratingKey: plan.media.id,
            state: state,
            time: max(0, Int(position * 1000)),
            duration: max(0, Int((plan.media.duration ?? 0) * 1000)),
            sessionIdentifier: playbackSessionID,
            playQueueItemID: queueItemIDs[plan.media.id]
        )
    }

    private static func search(
        query: String,
        kinds: Set<MediaKind>,
        context: PlexAPIContext,
        serverID: String,
        serverName: String,
        services: MediaServices
    ) async throws -> [MediaSearchSource] {
        let types: [SearchRepository.SearchType] = if kinds == [.movie] {
            [.movies]
        } else if kinds.isEmpty {
            [.movies, .tv]
        } else {
            [.tv]
        }
        let response = try await SearchRepository(context: context).search(
            params: .init(query: query, searchTypes: types, limit: 100)
        )
        return (response.mediaContainer.searchResult ?? []).compactMap(\.metadata)
            .compactMap(MediaDisplayItem.init)
            .filter { kinds.isEmpty || kinds.contains($0.playableItem?.kind ?? .unknown) }
            .map {
                MediaSearchSource(
                    serverIdentifier: serverID,
                    serverName: serverName,
                    media: $0,
                    services: services
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
            server: identity
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
            plexContext: context
        )
        adapter.services = services
        return services
    }
}
