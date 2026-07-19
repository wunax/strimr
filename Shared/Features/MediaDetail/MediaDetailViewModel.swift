import Foundation
import Observation
import SwiftUI

enum MediaDetailResolutionMode {
    case seriesRoot
    case selectedMedia
}

struct MediaDetailPlaybackTarget {
    let item: MediaItem
    let type: PlexItemType
    let shouldResumeFromOffset: Bool
}

@MainActor
@Observable
final class MediaDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let resolutionMode: MediaDetailResolutionMode

    var media: PlayableMediaItem
    var parentSeries: PlayableMediaItem?
    var onDeckItem: MediaItem?
    private var fallbackPlaybackTarget: MediaDetailPlaybackTarget?
    var heroImageURL: URL?
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []
    var seasons: [MediaItem] = []
    var episodes: [MediaItem] = []
    var cast: [CastMember] = []
    var relatedHubs: [Hub] = []
    var selectedSeasonId: String?
    var isLoadingSeasons = false
    var isLoadingEpisodes = false
    var isLoadingRelatedHubs = false
    var seasonsErrorMessage: String?
    var episodesErrorMessage: String?
    var relatedHubsErrorMessage: String?
    private var updatingWatchStatusIds: Set<String> = []
    var watchActionErrorMessage: String?
    var isLoadingWatchlistStatus = false
    var isUpdatingWatchlistStatus = false
    private var isWatchlisted = false
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(
        media: PlayableMediaItem,
        context: PlexAPIContext,
        resolutionMode: MediaDetailResolutionMode = .seriesRoot,
    ) {
        self.media = media
        self.context = context
        self.resolutionMode = resolutionMode
        resolveArtwork()
    }

    func loadDetails() async {
        _ = refreshGate.startInitialLoadIfNeeded()
        await loadDetails(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await loadDetails(preservingExistingContent: true)
    }

    private func loadDetails(preservingExistingContent: Bool) async {
        if !preservingExistingContent {
            cast = []
            relatedHubs = []
        }

        guard let metadataRepository = try? MetadataRepository(context: context) else {
            handleDetailLoadError(preservingExistingContent: preservingExistingContent)
            return
        }

        isLoading = true
        errorMessage = nil
        if !preservingExistingContent {
            onDeckItem = nil
            fallbackPlaybackTarget = nil
            watchActionErrorMessage = nil
        }

        do {
            let params = MetadataRepository.PlexMetadataParams(includeOnDeck: true)
            let response = try await metadataRepository.getMetadata(
                ratingKey: detailRatingKey,
                params: params,
            )
            if let item = response.mediaContainer.metadata?.first,
               let playable = PlayableMediaItem(plexItem: item)
            {
                media = playable
                cast = castMembers(from: item)
                resolveArtwork()
                resolveGradient()
            }
            onDeckItem = response.mediaContainer.metadata?.first?.onDeck?.metadata.map { MediaItem(plexItem: $0) }
            await loadParentSeries(using: metadataRepository)
            await loadWatchlistStatus()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                isLoading = false
                return
            }
            ErrorReporter.capture(error)
            if preservingExistingContent {
                errorMessage = nil
            } else {
                errorMessage = error.localizedDescription
            }
        }

        isLoading = false
        async let relatedHubsTask: Void = loadRelatedHubs(preservingExistingContent: preservingExistingContent)
        await loadSeriesChildren(preservingExistingContent: preservingExistingContent)
        await resolveFallbackPlaybackTarget(
            using: metadataRepository,
            preservingExistingContent: preservingExistingContent,
        )
        await relatedHubsTask
    }

    private var detailRatingKey: String {
        switch resolutionMode {
        case .seriesRoot:
            media.metadataRatingKey
        case .selectedMedia:
            media.id
        }
    }

    private func loadSeriesChildren(preservingExistingContent: Bool) async {
        switch media.type {
        case .show:
            await loadSeasonsIfNeeded(forceReload: true, preservingExistingContent: preservingExistingContent)
        case .season where resolutionMode == .selectedMedia:
            seasons = []
            selectedSeasonId = media.id
            await fetchEpisodes(for: media.id, preservingExistingContent: preservingExistingContent)
        case .movie, .episode, .season:
            seasons = []
            episodes = []
            selectedSeasonId = nil
        }
    }

    private func loadParentSeries(using metadataRepository: MetadataRepository) async {
        guard resolutionMode == .selectedMedia else {
            parentSeries = nil
            return
        }

        let seriesRatingKey: String?
        switch media.type {
        case .season:
            seriesRatingKey = media.mediaItem.parentRatingKey
        case .episode:
            seriesRatingKey = await resolveEpisodeSeriesRatingKey(using: metadataRepository)
        case .movie, .show:
            seriesRatingKey = nil
        }

        guard let seriesRatingKey else {
            parentSeries = nil
            return
        }

        do {
            let response = try await metadataRepository.getMetadata(ratingKey: seriesRatingKey)
            parentSeries = response.mediaContainer.metadata?.first.flatMap(PlayableMediaItem.init)
            resolveArtwork()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            parentSeries = nil
            ErrorReporter.capture(error)
        }
    }

    private func resolveEpisodeSeriesRatingKey(using metadataRepository: MetadataRepository) async -> String? {
        if let grandparentRatingKey = media.mediaItem.grandparentRatingKey {
            return grandparentRatingKey
        }

        guard let seasonRatingKey = media.mediaItem.parentRatingKey else { return nil }

        do {
            let response = try await metadataRepository.getMetadata(ratingKey: seasonRatingKey)
            return response.mediaContainer.metadata?.first?.parentRatingKey
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return nil }
            ErrorReporter.capture(error)
            return nil
        }
    }

    func loadSeasonsIfNeeded(forceReload: Bool = false, preservingExistingContent: Bool = false) async {
        guard media.type == .show else { return }
        guard forceReload || seasons.isEmpty else { return }
        await fetchSeasons(preservingExistingContent: preservingExistingContent)
    }

    func selectSeason(id: String) async {
        guard selectedSeasonId != id else { return }
        selectedSeasonId = id
        episodes = []
        episodesErrorMessage = nil
        await fetchEpisodes(for: id)
    }

    func toggleWatchStatus(for target: MediaItem? = nil) async {
        let item = target ?? media.mediaItem

        guard let scrobbleRepository = try? ScrobbleRepository(context: context) else {
            if target == nil {
                watchActionErrorMessage = String(localized: "errors.selectServer.updateWatchStatus")
            }
            return
        }

        guard !isUpdatingWatchStatus(for: item) else { return }

        updatingWatchStatusIds.insert(item.id)
        if target == nil {
            watchActionErrorMessage = nil
        }
        defer { updatingWatchStatusIds.remove(item.id) }

        do {
            if isWatched(item) {
                try await scrobbleRepository.markUnwatched(key: item.id)
            } else {
                try await scrobbleRepository.markWatched(key: item.id)
            }
            await loadDetails()
        } catch {
            if target == nil {
                watchActionErrorMessage = error.localizedDescription
            }
        }
    }

    func toggleWatchlistStatus() async {
        guard let discoverID = media.plexGuidID else { return }
        guard !isUpdatingWatchlistStatus else { return }
        guard let repository = try? DiscoverWatchlistRepository(context: context) else { return }

        isUpdatingWatchlistStatus = true
        defer { isUpdatingWatchlistStatus = false }

        do {
            if isWatchlisted {
                try await repository.removeFromWatchlist(ratingKey: discoverID)
            } else {
                try await repository.addToWatchlist(ratingKey: discoverID)
            }
            await loadWatchlistStatus()
        } catch {}
    }

    func imageURL(for media: MediaItem, width: Int = 320, height: Int = 180) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }

        let path = media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        return path.flatMap { imageRepository.transcodeImageURL(path: $0, width: width, height: height) }
    }

    private func resolveArtwork() {
        guard let imageRepository = try? ImageRepository(context: context) else {
            heroImageURL = nil
            return
        }

        let artPath: String?
        if resolutionMode == .selectedMedia, [.season, .episode].contains(media.type) {
            artPath = media.mediaItem.grandparentArtPath ?? parentSeries?.artPath ?? media.artPath
        } else {
            artPath = media.artPath
        }

        heroImageURL = artPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.thumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        }
        resolveGradient()
    }

    private func resolveGradient() {
        backdropGradient = MediaBackdropGradient.colors(for: .playable(media.mediaItem))
    }

    private func loadWatchlistStatus() async {
        guard [.movie, .show].contains(media.type) else {
            isWatchlisted = false
            return
        }

        guard let discoverID = media.plexGuidID else {
            isWatchlisted = false
            return
        }

        guard let repository = try? DiscoverWatchlistRepository(context: context) else {
            isWatchlisted = false
            return
        }

        isLoadingWatchlistStatus = true
        defer { isLoadingWatchlistStatus = false }

        do {
            let response = try await repository.getUserState(discoverID: discoverID)
            let userState = response.mediaContainer.userState?.first
            isWatchlisted = userState?.watchlistedAt != nil
        } catch {
            isWatchlisted = false
        }
    }

    var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        return duration.mediaDurationText()
    }

    var yearText: String? {
        media.year.map(String.init)
    }

    var ratingText: String? {
        media.rating.map { String(format: "%.1f", $0) }
    }

    var selectedSeason: MediaItem? {
        seasons.first(where: { $0.id == selectedSeasonId })
    }

    var selectedSeasonTitle: String {
        selectedSeason?.title ?? String(localized: "media.detail.season")
    }

    var detailPrimaryLabel: String {
        guard resolutionMode == .selectedMedia, [.season, .episode].contains(media.type) else {
            return media.primaryLabel
        }
        return media.title
    }

    var detailSecondaryLabel: String? {
        guard resolutionMode == .selectedMedia else { return media.secondaryLabel }

        switch media.type {
        case .season:
            return media.mediaItem.parentTitle
        case .episode:
            return media.mediaItem.grandparentTitle ?? media.mediaItem.parentTitle
        case .movie, .show:
            return media.secondaryLabel
        }
    }

    var detailTertiaryLabel: String? {
        media.tertiaryLabel
    }

    func runtimeText(for item: MediaItem) -> String? {
        guard let duration = item.duration else { return nil }
        return duration.mediaDurationText()
    }

    func castImageURL(for member: CastMember, width: Int = 200, height: Int = 260) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = member.thumbPath else { return nil }
        return imageRepository.transcodeImageURL(path: thumbPath, width: width, height: height)
    }

    var primaryActionTitle: String {
        guard let target = primaryPlaybackTarget else {
            return String(localized: "common.actions.play")
        }

        return target.shouldResumeFromOffset && hasProgress(for: target.item)
            ? String(localized: "common.actions.resume")
            : String(localized: "common.actions.play")
    }

    var primaryActionDetail: String? {
        guard let target = primaryPlaybackTarget else { return nil }
        let timeLeft = target.shouldResumeFromOffset ? timeLeftText(for: target.item) : nil

        switch media.type {
        case .movie, .episode:
            return timeLeft
        case .show, .season:
            let episodeLabel = seasonEpisodeLabel(for: target.item)
            if let timeLeft, let episodeLabel {
                return "\(episodeLabel) • \(timeLeft)"
            }
            return episodeLabel ?? timeLeft
        }
    }

    var primaryActionProgress: Double? {
        guard let target = primaryPlaybackTarget, target.shouldResumeFromOffset else { return nil }
        return progressFraction(for: target.item)
    }

    var shouldShowPlayFromStartButton: Bool {
        guard let target = primaryPlaybackTarget, target.shouldResumeFromOffset else { return false }
        return hasProgress(for: target.item)
    }

    var primaryActionRatingKey: String? {
        primaryPlaybackTarget?.item.id
    }

    var primaryActionType: PlexItemType? {
        primaryPlaybackTarget?.type
    }

    var primaryActionItem: MediaItem? {
        primaryPlaybackTarget?.item
    }

    var primaryActionInitialPosition: Double {
        guard let target = primaryPlaybackTarget, target.shouldResumeFromOffset else { return 0 }
        return Double(target.item.viewOffset ?? 0)
    }

    var shouldPlayPrimaryActionFromStart: Bool {
        guard let target = primaryPlaybackTarget else { return false }
        return !target.shouldResumeFromOffset
    }

    var isWatched: Bool {
        isWatched(media.mediaItem)
    }

    func playbackRatingKey() async -> String? {
        primaryActionRatingKey
    }

    private var primaryPlaybackTarget: MediaDetailPlaybackTarget? {
        switch media.type {
        case .movie, .episode:
            return MediaDetailPlaybackTarget(
                item: media.mediaItem,
                type: media.plexType,
                shouldResumeFromOffset: true,
            )
        case .show, .season:
            if let onDeckItem {
                return MediaDetailPlaybackTarget(
                    item: onDeckItem,
                    type: onDeckItem.type,
                    shouldResumeFromOffset: true,
                )
            }
            return fallbackPlaybackTarget
        }
    }

    var watchActionTitle: String {
        watchActionTitle(for: media.mediaItem)
    }

    var watchActionIcon: String {
        watchActionIcon(for: media.mediaItem)
    }

    var watchlistActionTitle: String {
        isWatchlisted
            ? String(localized: "media.detail.watchlist.remove")
            : String(localized: "media.detail.watchlist.add")
    }

    var watchlistActionIcon: String {
        isWatchlisted ? "bookmark.fill" : "bookmark"
    }

    var shouldShowWatchlistButton: Bool {
        [.movie, .show].contains(media.type)
            && media.plexGuidID != nil
    }

    var isUpdatingWatchStatus: Bool {
        isUpdatingWatchStatus(for: media.mediaItem)
    }

    func isWatched(_ item: MediaItem) -> Bool {
        guard let playableType = PlayableItemType(plexType: item.type) else { return false }

        switch playableType {
        case .movie, .episode:
            return (item.viewCount ?? 0) > 0
        case .show, .season:
            guard let leafCount = item.leafCount, let viewedLeafCount = item.viewedLeafCount else {
                return false
            }
            guard leafCount > 0 else { return false }
            return leafCount == viewedLeafCount
        }
    }

    func watchActionTitle(for item: MediaItem) -> String {
        isWatched(item)
            ? String(localized: "media.detail.watchAction.markUnwatched")
            : String(localized: "media.detail.watchAction.markWatched")
    }

    func watchActionIcon(for item: MediaItem) -> String {
        isWatched(item) ? "checkmark.circle.fill" : "checkmark.circle"
    }

    func isUpdatingWatchStatus(for item: MediaItem) -> Bool {
        updatingWatchStatusIds.contains(item.id)
    }

    func progressFraction(for item: MediaItem) -> Double? {
        guard let percentage = item.viewProgressPercentage else { return nil }
        return min(1, max(0, percentage / 100))
    }

    private func hasProgress(for item: MediaItem?) -> Bool {
        guard let viewOffset = item?.viewOffset else { return false }
        return viewOffset > 0
    }

    private func timeLeftText(for item: MediaItem?) -> String? {
        guard
            let item,
            let duration = item.duration,
            let viewOffset = item.viewOffset,
            viewOffset > 0
        else {
            return nil
        }

        let remaining = max(0, duration - viewOffset)
        guard remaining > 0 else { return nil }

        return String(localized: "media.detail.timeLeft \(remaining.mediaDurationText())")
    }

    private func seasonEpisodeLabel(for item: MediaItem) -> String? {
        guard let season = item.parentIndex, let episode = item.index else { return nil }
        return String(localized: "media.detail.seasonEpisode \(season) \(episode)")
    }

    private func fetchSeasons(preservingExistingContent: Bool) async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            if !preservingExistingContent || seasons.isEmpty {
                seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
            }
            return
        }

        isLoadingSeasons = true
        seasonsErrorMessage = nil
        episodesErrorMessage = nil
        defer { isLoadingSeasons = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: detailRatingKey)
            let fetchedSeasons = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
            seasons = fetchedSeasons
            episodes = []

            guard !fetchedSeasons.isEmpty else {
                selectedSeasonId = nil
                episodes = []
                return
            }

            let nextSeasonId = preferredSeasonId(in: fetchedSeasons)
            selectedSeasonId = nextSeasonId

            if let seasonId = nextSeasonId {
                await fetchEpisodes(for: seasonId, preservingExistingContent: preservingExistingContent)
            } else {
                episodes = []
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if preservingExistingContent, !seasons.isEmpty {
                seasonsErrorMessage = nil
            } else {
                seasons = []
                selectedSeasonId = nil
                episodes = []
                seasonsErrorMessage = error.localizedDescription
            }
        }
    }

    private func preferredSeasonId(in fetchedSeasons: [MediaItem]) -> String? {
        if let selectedSeasonId,
           fetchedSeasons.contains(where: { $0.id == selectedSeasonId })
        {
            return selectedSeasonId
        }

        if let onDeckSeasonIndex = onDeckItem?.parentIndex,
           let onDeckSeason = fetchedSeasons.first(where: { $0.index == onDeckSeasonIndex })
        {
            return onDeckSeason.id
        }

        return fetchedSeasons.first(where: { ($0.index ?? 0) > 0 })?.id
            ?? fetchedSeasons.first?.id
    }

    private func fetchEpisodes(for seasonId: String, preservingExistingContent: Bool = false) async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            if !preservingExistingContent || episodes.isEmpty {
                episodesErrorMessage = String(localized: "errors.selectServer.loadEpisodes")
            }
            return
        }

        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: seasonId)
            let fetchedEpisodes = (response.mediaContainer.metadata ?? []).map(MediaItem.init)

            guard selectedSeasonId == seasonId else { return }
            episodes = fetchedEpisodes
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if selectedSeasonId == seasonId {
                if preservingExistingContent, !episodes.isEmpty {
                    episodesErrorMessage = nil
                } else {
                    episodes = []
                    episodesErrorMessage = error.localizedDescription
                }
            }
        }
    }

    private func resolveFallbackPlaybackTarget(
        using metadataRepository: MetadataRepository,
        preservingExistingContent: Bool,
    ) async {
        guard onDeckItem == nil else {
            fallbackPlaybackTarget = nil
            return
        }

        switch media.type {
        case .movie, .episode:
            fallbackPlaybackTarget = nil
        case .season:
            fallbackPlaybackTarget = playbackFallback(from: episodes, sortBySeason: false)
        case .show:
            do {
                let response = try await metadataRepository.getMetadataGrandChildren(ratingKey: detailRatingKey)
                let allEpisodes = (response.mediaContainer.metadata ?? [])
                    .map(MediaItem.init)
                    .filter { $0.type == .episode }
                let regularEpisodes = allEpisodes.filter { ($0.parentIndex ?? 0) > 0 }
                let eligibleEpisodes = regularEpisodes.isEmpty ? allEpisodes : regularEpisodes
                fallbackPlaybackTarget = playbackFallback(from: eligibleEpisodes, sortBySeason: true)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
                if !preservingExistingContent {
                    fallbackPlaybackTarget = nil
                }
            }
        }
    }

    private func playbackFallback(
        from episodes: [MediaItem],
        sortBySeason: Bool,
    ) -> MediaDetailPlaybackTarget? {
        let sortedEpisodes = episodes.sorted { lhs, rhs in
            if sortBySeason {
                let lhsSeason = lhs.parentIndex ?? Int.max
                let rhsSeason = rhs.parentIndex ?? Int.max
                if lhsSeason != rhsSeason {
                    return lhsSeason < rhsSeason
                }
            }

            let lhsEpisode = lhs.index ?? Int.max
            let rhsEpisode = rhs.index ?? Int.max
            if lhsEpisode != rhsEpisode {
                return lhsEpisode < rhsEpisode
            }
            return lhs.id < rhs.id
        }

        guard let item = sortedEpisodes.first(where: { !$0.isFullyWatched }) ?? sortedEpisodes.first else {
            return nil
        }

        return MediaDetailPlaybackTarget(
            item: item,
            type: item.type,
            shouldResumeFromOffset: !item.isFullyWatched,
        )
    }

    private func castMembers(from item: PlexItem?) -> [CastMember] {
        guard let roles = item?.roles, !roles.isEmpty else { return [] }

        return roles.map { role in
            let identifier = role.id.map(String.init) ?? "\(role.tag)-\(role.role ?? "role")"
            let character = role.role?.isEmpty == false ? role.role : nil
            return CastMember(
                id: identifier,
                name: role.tag,
                character: character,
                thumbPath: role.thumb,
            )
        }
    }

    func loadRelatedHubs(preservingExistingContent: Bool = false) async {
        guard let hubRepository = try? HubRepository(context: context) else {
            if !preservingExistingContent || relatedHubs.isEmpty {
                relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
            }
            return
        }

        isLoadingRelatedHubs = true
        relatedHubsErrorMessage = nil
        defer { isLoadingRelatedHubs = false }

        do {
            let response = try await hubRepository.getRelatedMediaHubs(ratingKey: detailRatingKey)
            relatedHubs = (response.mediaContainer.hub ?? []).map(Hub.init)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if preservingExistingContent, !relatedHubs.isEmpty {
                relatedHubsErrorMessage = nil
            } else {
                relatedHubs = []
                relatedHubsErrorMessage = error.localizedDescription
            }
        }
    }

    private func handleDetailLoadError(preservingExistingContent: Bool) {
        if preservingExistingContent {
            errorMessage = nil
            return
        }

        errorMessage = String(localized: "errors.selectServer.loadDetails")
        if media.type == .show {
            seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
        }
        relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
    }
}
