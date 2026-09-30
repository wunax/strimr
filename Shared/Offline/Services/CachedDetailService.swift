import Foundation

@MainActor
final class CachedDetailService: MediaDetailService {
    private let base: any MediaDetailService
    private let policy: OfflineCachePolicy

    init(base: any MediaDetailService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    private var store: OfflineStore {
        policy.store
    }

    private var owner: MediaOwner {
        policy.owner
    }

    var supportsWatchlist: Bool {
        base.supportsWatchlist
    }

    var supportsRemoteSubtitleSearch: Bool {
        base.supportsRemoteSubtitleSearch
    }

    var supportsAdvancedSubtitleSearch: Bool {
        base.supportsAdvancedSubtitleSearch
    }

    func mediaItem(id: String) async throws -> MediaItem {
        try await policy.read(
            network: { try await base.mediaItem(id: id) },
            write: { store.store(media: [$0], owner: owner) },
            fallback: { store.media(id: id, owner: owner) },
            onNotFound: { [self] in itemDisappeared(id) },
        ).overlaid(by: policy)
    }

    func libraryID(for media: MediaItem) async throws -> String? {
        try await policy.online { try await base.libraryID(for: media) }
    }

    func searchSubtitles(
        itemID: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?,
    ) async throws -> [RemoteSubtitleResult] {
        try await policy.online {
            try await base.searchSubtitles(
                itemID: itemID,
                language: language,
                hearingImpaired: hearingImpaired,
                forced: forced,
                title: title,
            )
        }
    }

    func installSubtitle(itemID: String, result: RemoteSubtitleResult) async throws {
        try await policy.online { try await base.installSubtitle(itemID: itemID, result: result) }
    }

    func details(for media: MediaItem) async throws -> MediaDetailContent {
        let content = try await policy.read(
            network: { try await base.details(for: media) },
            write: { store.store(detail: $0, owner: owner) },
            fallback: { cachedDetails(for: media) },
            onNotFound: { [self] in itemDisappeared(media.id) },
        )
        return MediaDetailContent(
            media: content.media.overlaid(by: policy),
            parentSeries: content.parentSeries,
            onDeck: content.onDeck.map { $0.overlaid(by: policy) },
            seasons: content.seasons,
            episodes: policy.overlayLocalProgress(content.episodes),
            cast: content.cast,
            relatedHubs: content.relatedHubs,
        )
    }

    /// Detail content rebuilt from the cache: full details when the page was visited, else the pinned minimum.
    func cachedDetails(for media: MediaItem) -> MediaDetailContent? {
        guard let cached = store.media(id: media.id, owner: owner) ?? (policy.isUnreachable ? media : nil) else {
            return nil
        }
        let seriesID: String? = switch cached.kind {
        case .episode:
            cached.grandparentRatingKey
        case .season:
            cached.parentRatingKey
        default:
            nil
        }
        return MediaDetailContent(
            media: cached,
            parentSeries: seriesID.flatMap { store.media(id: $0, owner: owner) },
            onDeck: nil,
            seasons: cached.kind == .series ? store.children(of: cached.id, kind: .season, owner: owner) : [],
            episodes: cached.kind == .season ? store.children(of: cached.id, kind: .episode, owner: owner) : [],
            cast: store.cast(for: cached.id, owner: owner) ?? [],
            relatedHubs: [],
        )
    }

    func fileInfo(for media: MediaItem) async throws -> MediaFileInfo? {
        try await policy.online { try await base.fileInfo(for: media) }
    }

    func fetchExtras(for media: MediaItem) async throws -> [MediaItem] {
        guard !policy.isUnreachable else { return [] }
        return try await policy.online { try await base.fetchExtras(for: media) }
    }

    func seasons(for series: MediaItem) async throws -> [MediaItem] {
        try await policy.read(
            network: { try await base.seasons(for: series) },
            write: { store.store(media: $0, owner: owner) },
            fallback: { store.children(of: series.id, kind: .season, owner: owner) },
        )
    }

    func episodes(for season: MediaItem, seriesID: String?) async throws -> [MediaItem] {
        try await policy.overlayLocalProgress(policy.read(
            network: { try await base.episodes(for: season, seriesID: seriesID) },
            write: { store.store(media: $0, owner: owner) },
            fallback: { store.children(of: season.id, kind: .episode, owner: owner) },
        ))
    }

    func allEpisodes(for series: MediaItem) async throws -> [MediaItem] {
        try await policy.overlayLocalProgress(policy.read(
            network: { try await base.allEpisodes(for: series) },
            write: { store.store(media: $0, owner: owner) },
            fallback: { store.episodes(ofSeries: series.id, owner: owner) },
        ))
    }

    func setPlayed(_ played: Bool, itemID: String) async throws {
        try await policy.online { try await base.setPlayed(played, itemID: itemID) }
    }

    func isWatchlisted(_ media: MediaItem) async throws -> Bool {
        try await policy.online { try await base.isWatchlisted(media) }
    }

    func setWatchlisted(_ watchlisted: Bool, media: MediaItem) async throws {
        try await policy.online { try await base.setWatchlisted(watchlisted, media: media) }
    }

    func trackSelection(itemID: String) async throws -> MediaTrackSelection {
        try await policy.online { try await base.trackSelection(itemID: itemID) }
    }

    func selectAudioTrack(id: Int, itemID: String) async throws {
        try await policy.online { try await base.selectAudioTrack(id: id, itemID: itemID) }
    }

    func selectSubtitleTrack(id: Int?, itemID: String) async throws {
        try await policy.online { try await base.selectSubtitleTrack(id: id, itemID: itemID) }
    }

    func collectionItems(id: String) async throws -> [MediaDisplayItem] {
        try await cachedList(key: "collection:\(id)") { try await base.collectionItems(id: id) }
    }

    func playlistItems(id: String) async throws -> [MediaDisplayItem] {
        try await cachedList(key: "playlist:\(id)") { try await base.playlistItems(id: id) }
    }

    func person(id: String) async throws -> Person {
        let key = "person:\(id)"
        return try await policy.read(
            network: { try await base.person(id: id) },
            write: { person in
                store.store(list: [], key: key, payload: store.encode(person), owner: owner)
            },
            fallback: {
                store.list(key: key, owner: owner)?.payload.flatMap { store.decode(Person.self, from: $0) }
            },
        )
    }

    /// Offline, a person page can only be opened when it was visited before.
    func canOpenPerson(id: String) -> Bool {
        !policy.isUnreachable || store.list(key: "person:\(id)", owner: owner) != nil
    }

    func personMedia(id: String) async throws -> [MediaDisplayItem] {
        try await cachedList(key: "personMedia:\(id)") { try await base.personMedia(id: id) }
    }

    private func cachedList(
        key: String,
        network: () async throws -> [MediaDisplayItem],
    ) async throws -> [MediaDisplayItem] {
        try await policy.overlayLocalProgress(policy.read(
            network: network,
            write: { store.store(list: $0, key: key, owner: owner) },
            fallback: { store.list(key: key, owner: owner)?.items },
        ))
    }

    /// A 404 online removes the item from the browsing cache; a downloaded copy stays playable.
    private func itemDisappeared(_ itemID: String) {
        store.removeMedia(itemID: itemID, owner: owner)
        DownloadManager.shared?.markOrphaned(itemID: itemID, owner: owner)
    }
}

private extension MediaItem {
    func overlaid(by policy: OfflineCachePolicy) -> MediaItem {
        policy.overlayLocalProgress([self]).first ?? self
    }
}
