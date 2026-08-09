import AetherEngine
import Foundation

@MainActor
final class JellyfinMediaServiceAdapter: MediaHomeService, MediaLibraryService, MediaSearchService,
    MediaArtworkService, MediaDetailService, MediaPlaybackService, MediaDownloadService
{
    private let context: JellyfinAPIContext
    private let catalog: JellyfinCatalogService
    private let playbackService: JellyfinPlaybackService
    private let server: ServerIdentity
    private var activePlans: [String: JellyfinPlaybackPlan] = [:]
    weak var services: MediaServices?

    init(context: JellyfinAPIContext, server: ServerIdentity) {
        self.context = context
        self.server = server
        catalog = JellyfinCatalogService(context: context)
        playbackService = JellyfinPlaybackService(context: context)
    }

    var supportsWatchlist: Bool { false }
    var supportsRemoteSubtitleSearch: Bool { true }

    func mediaItem(id: String) async throws -> MediaItem {
        MediaItem(jellyfinItem: try await catalog.item(id: id), server: server)
    }

    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title _: String?
    ) async throws -> [RemoteSubtitleResult] {
        let values: [JellyfinRemoteSubtitle] = try await context.get(
            path: ["Items", itemID, "RemoteSearch", "Subtitles", language]
        )
        return values.filter { value in
            (!forced || value.isForced == true)
                && (!hearingImpaired || value.hearingImpaired == true)
        }.map { value in
            RemoteSubtitleResult(
                id: value.id,
                title: value.name ?? value.providerName ?? value.id,
                language: value.threeLetterISOLanguageName,
                codec: value.format ?? "",
                providerTitle: value.providerName
            )
        }
    }

    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws {
        try await context.send(
            path: ["Items", itemID, "RemoteSearch", "Subtitles", result.id],
            method: "POST"
        )
    }

    func loadHome(hiddenLibraryIDs: Set<String>, includesPlaylists _: Bool) async throws -> HomeContent {
        let visibleLibraries = try await catalog.libraries().filter { !hiddenLibraryIDs.contains($0.id) }
        async let resumeItems = catalog.resume()
        async let nextUpItems = catalog.nextUp()
        let resume = try await resumeItems
        let nextUp = try await nextUpItems

        var hubs: [Hub] = []
        if !nextUp.isEmpty {
            hubs.append(hub(id: "jellyfin.nextUp", title: String(localized: "jellyfin.home.nextUp"), items: nextUp))
        }
        let latest = try await withThrowingTaskGroup(of: (Int, JellyfinItem, [JellyfinItem]).self) { group in
            for (index, library) in visibleLibraries.enumerated() {
                group.addTask { [catalog] in
                    let items = try await catalog.latest(
                        types: library.collectionType == "tvshows" ? "Series" : "Movie",
                        parentID: library.id
                    )
                    return (index, library, items)
                }
            }
            var values: [(Int, JellyfinItem, [JellyfinItem])] = []
            for try await value in group { values.append(value) }
            return values.sorted { $0.0 < $1.0 }
        }
        hubs.append(contentsOf: latest.compactMap { _, library, items in
            guard !items.isEmpty else { return nil }
            return hub(
                id: "jellyfin.latest.\(library.id)",
                title: String(localized: "jellyfin.home.latestIn \(library.name)"),
                items: items
            )
        })

        return HomeContent(
            continueWatching: resume.isEmpty
                ? nil
                : hub(id: "jellyfin.resume", title: String(localized: "jellyfin.home.resume"), items: resume),
            recentlyAdded: hubs
        )
    }

    func libraries() async throws -> [Library] {
        try await catalog.libraries().map(Library.init)
    }

    func randomArtwork(for library: Library) async throws -> ArtworkResource? {
        let type = library.type == .series ? "Series" : "Movie"
        guard let item = try await catalog.latest(types: type, parentID: library.id, limit: 1).first else {
            return nil
        }
        let media = MediaDisplayItem.playable(MediaItem(jellyfinItem: item, server: server))
        return try await artwork(for: media, kind: .art, width: 800, height: 450)
    }

    func recommended(in library: Library) async throws -> [Hub] {
        let type = library.type == .series ? "Series" : "Movie"
        let items = try await catalog.latest(types: type, parentID: library.id, limit: 20)
        guard !items.isEmpty else { return [] }
        return [hub(
            id: "jellyfin.library.latest.\(library.id)",
            title: String(localized: "jellyfin.home.latestIn \(library.title)"),
            items: items
        )]
    }

    func items(
        in library: Library,
        parentID: String?,
        startIndex: Int,
        limit: Int
    ) async throws -> MediaPage<MediaDisplayItem> {
        let response = try await catalog.items(
            parentID: parentID ?? library.id,
            includeTypes: library.type == .series ? "Series,Season,Episode" : "Movie",
            recursive: parentID == nil,
            startIndex: startIndex,
            limit: limit
        )
        return MediaPage(
            items: response.items.compactMap { MediaDisplayItem(jellyfinItem: $0, server: server) },
            startIndex: response.startIndex ?? startIndex,
            totalCount: response.totalRecordCount
        )
    }

    func collections(in _: Library) async throws -> [CollectionMediaItem] {
        try await catalog.items(includeTypes: "BoxSet", limit: 100).items.compactMap {
            guard case let .collection(item) = MediaDisplayItem(jellyfinItem: $0, server: server) else { return nil }
            return item
        }
    }

    func playlists(in _: Library) async throws -> [PlaylistMediaItem] {
        try await catalog.items(includeTypes: "Playlist", limit: 100).items.compactMap {
            guard case let .playlist(item) = MediaDisplayItem(jellyfinItem: $0, server: server) else { return nil }
            return item
        }
    }

    func search(
        query: String,
        kinds: Set<MediaKind>,
        searchesAllServers _: Bool
    ) async throws -> [MediaSearchSource] {
        guard let services else { return [] }
        let includeTypes = searchTypes(for: kinds)
        let response = try await catalog.items(
            includeTypes: includeTypes,
            searchTerm: query,
            limit: 100
        )
        let name = context.connection?.serverName ?? "Jellyfin"
        return response.items.compactMap { item in
            guard let media = MediaDisplayItem(jellyfinItem: item, server: server) else { return nil }
            return MediaSearchSource(
                serverIdentifier: server.id,
                serverName: name,
                media: media,
                services: services
            )
        }
    }

    func artwork(
        for media: MediaDisplayItem,
        kind: MediaImageViewModel.ArtworkKind,
        width: Int?,
        height: Int?
    ) async throws -> ArtworkResource? {
        let path = kind == .thumb ? media.preferredThumbPath : media.preferredArtPath
        return try await artwork(path: path, width: width, height: height)
    }

    func artwork(path: String?, width: Int?, height: Int?) async throws -> ArtworkResource? {
        guard let path, let descriptor = JellyfinArtworkPath.parse(path) else { return nil }
        var query = [URLQueryItem(name: "quality", value: "90")]
        if let descriptorTag = descriptor.tag {
            query.append(URLQueryItem(name: "tag", value: descriptorTag))
        }
        if let width { query.append(URLQueryItem(name: "maxWidth", value: String(width))) }
        if let height { query.append(URLQueryItem(name: "maxHeight", value: String(height))) }
        let url = try context.url(
            path: ["Items", descriptor.ownerID, "Images", descriptor.type],
            query: query
        )
        let request = try context.mediaRequest(url: url)
        return .data(try await context.data(for: request))
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        let item = try await catalog.item(id: media.id)
        let mapped = MediaItem(jellyfinItem: item, server: server)
        let seasons: [MediaItem]
        let episodes: [MediaItem]
        switch item.kind {
        case .series:
            seasons = try await catalog.seasons(seriesID: item.id).map { MediaItem(jellyfinItem: $0, server: server) }
            episodes = []
        case .season:
            seasons = []
            let seriesID = item.seriesID ?? item.parentID
            episodes = if let seriesID {
                try await catalog.episodes(seriesID: seriesID, seasonID: item.id)
                    .map { MediaItem(jellyfinItem: $0, server: server) }
            } else { [] }
        default:
            seasons = []
            episodes = []
        }
        let related = try await catalog.similar(itemID: item.id)
        let relatedHub = related.isEmpty ? [] : [hub(
            id: "jellyfin.similar.\(item.id)",
            title: String(localized: "jellyfin.detail.similar"),
            items: related
        )]
        return MediaDetailContent(
            media: mapped,
            parentSeries: nil,
            onDeck: item.kind == .series ? try await catalog.nextUp(seriesID: item.id, limit: 1).first.map {
                MediaItem(jellyfinItem: $0, server: server)
            } : nil,
            seasons: seasons,
            episodes: episodes,
            cast: (item.people ?? []).map {
                CastMember(
                    id: $0.id,
                    personID: $0.id,
                    name: $0.name,
                    character: $0.role,
                    thumbPath: JellyfinArtworkPath.make(
                        ownerID: $0.id,
                        type: "Primary",
                        tag: $0.primaryImageTag
                    )
                )
            },
            relatedHubs: relatedHub
        )
    }

    func seasons(for series: MediaItem) async throws -> [MediaItem] {
        try await catalog.seasons(seriesID: series.id).map { MediaItem(jellyfinItem: $0, server: server) }
    }

    func episodes(for season: MediaItem, seriesID: String?) async throws -> [MediaItem] {
        guard let seriesID = seriesID ?? season.grandparentRatingKey ?? season.parentRatingKey else { return [] }
        return try await catalog.episodes(seriesID: seriesID, seasonID: season.id)
            .map { MediaItem(jellyfinItem: $0, server: server) }
    }

    func setPlayed(_ played: Bool, itemID: String) async throws {
        try await catalog.markPlayed(itemID: itemID, played: played)
    }

    func collectionItems(id: String) async throws -> [MediaDisplayItem] {
        try await childItems(id: id)
    }

    func playlistItems(id: String) async throws -> [MediaDisplayItem] {
        try await childItems(id: id)
    }

    func person(id: String) async throws -> Person {
        let value: JellyfinPerson = try await context.get(path: ["Persons", id])
        return Person(jellyfinPerson: value)
    }

    func personMedia(id: String) async throws -> [MediaDisplayItem] {
        try await catalog.items(includeTypes: "Movie,Series,Episode", personID: id, limit: 100).items
            .compactMap { MediaDisplayItem(jellyfinItem: $0, server: server) }
    }

    func queue(startingWith media: MediaItem, shuffle: Bool) async throws -> PlaybackQueue {
        let item = try await catalog.item(id: media.id)
        var values = try await catalog.playbackQueue(startingWith: item)
        if shuffle { values.shuffle() }
        let queueItems = values.map {
            PlaybackQueueItem(
                id: UUID(),
                media: MediaItem(jellyfinItem: $0, server: server),
                providerQueueItemID: nil
            )
        }
        return PlaybackQueue(
            id: UUID(),
            items: queueItems,
            currentIndex: queueItems.firstIndex(where: { $0.media.id == media.id }) ?? 0,
            isShuffled: shuffle
        )
    }

    func queue(startingWith itemID: String, kind: MediaKind, shuffle: Bool) async throws -> PlaybackQueue {
        let item = try await catalog.item(id: itemID)
        return try await queue(startingWith: MediaItem(jellyfinItem: item, server: server), shuffle: shuffle)
    }

    func prepare(media: MediaItem, resume: Bool) async throws -> PlaybackPlan {
        let item = try await catalog.item(id: media.id)
        let plan = try await playbackService.prepare(item: item, resume: resume)
        activePlans[plan.playSessionID] = plan
        let segments = (try? await catalog.mediaSegments(itemID: item.id)) ?? []
        let tracks = (item.mediaSources?.first?.mediaStreams ?? []).compactMap { stream -> PlaybackTrack? in
            let kind: PlaybackTrackKind
            switch stream.type.lowercased() {
            case "audio": kind = .audio
            case "subtitle": kind = .subtitle
            default: return nil
            }
            return PlaybackTrack(
                id: "jellyfin.\(stream.index)",
                sourceIndex: stream.index,
                kind: kind,
                title: stream.displayTitle ?? stream.language ?? stream.codec ?? "",
                language: stream.language,
                codec: stream.codec,
                isDefault: stream.isDefault ?? false,
                isForced: stream.isForced ?? false,
                isHearingImpaired: false
            )
        }
        let scrubSource: ScrubThumbnailSource? = {
            guard let variants = item.trickplay?[plan.mediaSourceID],
                  let info = variants.values
                    .filter({ $0.width > 0 && $0.height > 0 && $0.interval > 0 })
                    .sorted(by: { lhs, rhs in
                        let lhsDistance = abs(lhs.width - 320)
                        let rhsDistance = abs(rhs.width - 320)
                        return lhsDistance == rhsDistance ? lhs.width < rhs.width : lhsDistance < rhsDistance
                    })
                    .first,
                  let directoryURL = try? context.url(
                      path: ["Videos", item.id, "Trickplay", String(info.width)]
                  )
            else { return nil }
            return .jellyfin(JellyfinTrickplaySource(
                directoryURL: directoryURL,
                headers: plan.headers,
                cacheKey: "\(server.id):\(item.id):\(plan.mediaSourceID):\(info.width)",
                mediaSourceID: plan.mediaSourceID,
                width: info.width,
                height: info.height,
                tileColumns: info.tileWidth,
                tileRows: info.tileHeight,
                thumbnailCount: info.thumbnailCount,
                intervalMilliseconds: info.interval
            ))
        }()
        return PlaybackPlan(
            media: MediaItem(jellyfinItem: item, server: server),
            url: plan.url,
            httpHeaders: plan.headers,
            method: .directPlay,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            initialPosition: plan.initialPosition,
            selectedAudioIndex: plan.preferredAudioStreamIndex,
            selectedSubtitleIndex: plan.preferredSubtitleStreamIndex,
            tracks: tracks,
            externalSubtitles: plan.externalSubtitles,
            chapters: plan.chapters.enumerated().map { index, chapter in
                let nextStart = plan.chapters.indices.contains(index + 1)
                    ? plan.chapters[index + 1].startTime
                    : item.duration ?? (chapter.startTime + 1)
                return MediaChapter(
                    id: String(chapter.startPositionTicks),
                    title: chapter.name ?? "",
                    index: index + 1,
                    startTime: chapter.startTime,
                    endTime: max(chapter.startTime + 0.001, nextStart),
                    image: nil,
                    thumbPath: nil
                )
            },
            skipSegments: segments.compactMap { segment in
                let kind: SkipSegment.Kind
                switch segment.type.lowercased() {
                case "intro": kind = .intro
                case "outro", "credits": kind = .credits
                default: return nil
                }
                return SkipSegment(
                    id: segment.id ?? "\(segment.type).\(segment.startTicks)",
                    kind: kind,
                    startTime: JellyfinTime.seconds(fromTicks: segment.startTicks),
                    endTime: JellyfinTime.seconds(fromTicks: segment.endTicks)
                )
            },
            scrubThumbnailSource: scrubSource
        )
    }

    func reportStarted(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        guard let source = sourcePlan(for: plan) else { return }
        try await playbackService.reportStarted(plan: source, position: position, isPaused: isPaused)
    }

    func reportProgress(plan: PlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        guard let source = sourcePlan(for: plan) else { return }
        try await playbackService.reportProgress(plan: source, position: position, isPaused: isPaused)
    }

    func reportStopped(plan: PlaybackPlan, position: TimeInterval) async throws {
        guard let source = sourcePlan(for: plan) else { return }
        defer { activePlans[source.playSessionID] = nil }
        try await playbackService.reportStopped(plan: source, position: position)
    }

    func externalSubtitles(media: MediaItem) async throws -> [ExternalSubtitleTrack] {
        try playbackService.externalSubtitles(item: try await catalog.item(id: media.id))
    }

    func prepareDownload(itemID: String) async throws -> MediaDownloadPreparation {
        let item = try await catalog.item(id: itemID)
        guard item.isPlayable, item.canDownload != false else {
            throw JellyfinAPIError.permissionDenied
        }
        let url = try context.url(path: ["Items", item.id, "Download"])
        return MediaDownloadPreparation(
            media: MediaItem(jellyfinItem: item, server: server),
            request: try context.mediaRequest(url: url)
        )
    }

    func downloadableItems(itemID: String, kind: MediaKind) async throws -> [MediaItem] {
        let item = try await catalog.item(id: itemID)
        if kind == .movie || kind == .episode {
            return [MediaItem(jellyfinItem: item, server: server)]
        }
        return try await catalog.playbackQueue(startingWith: item)
            .filter(\.isPlayable)
            .map { MediaItem(jellyfinItem: $0, server: server) }
    }

    private func sourcePlan(for plan: PlaybackPlan) -> JellyfinPlaybackPlan? {
        plan.playSessionID.flatMap { activePlans[$0] }
    }

    private func childItems(id: String) async throws -> [MediaDisplayItem] {
        try await catalog.items(
            parentID: id,
            includeTypes: "Movie,Series,Season,Episode",
            recursive: false,
            limit: 500
        ).items.compactMap { MediaDisplayItem(jellyfinItem: $0, server: server) }
    }

    private func hub(id: String, title: String, items: [JellyfinItem]) -> Hub {
        Hub(
            id: id,
            key: id,
            hubKey: nil,
            title: title,
            size: items.count,
            more: false,
            items: items.compactMap { MediaDisplayItem(jellyfinItem: $0, server: server) }
        )
    }

    private func searchTypes(for kinds: Set<MediaKind>) -> String {
        guard !kinds.isEmpty else { return "Movie,Series,Season,Episode,BoxSet,Playlist" }
        return kinds.map {
            switch $0 {
            case .movie: "Movie"
            case .series: "Series"
            case .season: "Season"
            case .episode: "Episode"
            case .collection: "BoxSet"
            case .playlist: "Playlist"
            case .folder: "Folder"
            case .unknown: ""
            }
        }.filter { !$0.isEmpty }.joined(separator: ",")
    }
}

@MainActor
enum JellyfinMediaServicesFactory {
    static func make(context: JellyfinAPIContext, capabilities: ProviderCapabilities) -> MediaServices? {
        guard let connection = context.connection else { return nil }
        let adapter = JellyfinMediaServiceAdapter(context: context, server: connection.serverIdentity)
        let services = MediaServices(
            provider: .jellyfin,
            identity: connection.serverIdentity,
            capabilities: capabilities,
            home: adapter,
            library: adapter,
            search: adapter,
            artwork: adapter,
            detail: adapter,
            playback: adapter,
            downloads: adapter
        )
        adapter.services = services
        return services
    }
}
