import Foundation
import Observation
import SwiftUI

enum MediaDetailResolutionMode {
    case seriesRoot
    case selectedMedia
}

struct MediaDetailPlaybackTarget {
    let item: MediaItem
    let type: MediaKind
    let shouldResumeFromOffset: Bool
}

@MainActor
@Observable
final class MediaDetailViewModel {
    @ObservationIgnored private let services: MediaServices
    @ObservationIgnored private let resolutionMode: MediaDetailResolutionMode
    @ObservationIgnored private var backdropSourcePath: String?

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
    var audioTracks: [MediaTrackMetadata] = []
    var subtitleTracks: [MediaTrackMetadata] = []
    var selectedAudioStreamID: Int?
    var selectedSubtitleStreamID: Int?
    var isLoadingTracks = false
    var isUpdatingTracks = false
    var trackSelectionErrorMessage: String?
    @ObservationIgnored private var trackPartFile: String?
    @ObservationIgnored private(set) var trackRatingKey: String?
    @ObservationIgnored private var requestedTrackRatingKey: String?
    private var updatingWatchStatusIds: Set<String> = []
    var watchActionErrorMessage: String?
    var isLoadingWatchlistStatus = false
    var isUpdatingWatchlistStatus = false
    private var isWatchlisted = false
    var isLoadingFavoriteStatus = false
    var isUpdatingFavoriteStatus = false
    private(set) var isFavorite = false
    var favoriteActionErrorMessage: String?
    private var favoriteStatusByID: [String: Bool] = [:]
    private var loadingFavoriteStatusIDs: Set<String> = []
    private var updatingFavoriteStatusIDs: Set<String> = []
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(
        media: PlayableMediaItem,
        services: MediaServices,
        resolutionMode: MediaDetailResolutionMode = .seriesRoot,
    ) {
        self.media = media
        self.services = services
        self.resolutionMode = resolutionMode
        _ = resolveArtwork()
    }

    var serverIdentifier: String? {
        services.identity.id
    }

    private var detailTargetID: String {
        resolutionMode == .seriesRoot ? media.metadataRatingKey : media.id
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
        await loadCommonDetails(preservingExistingContent: preservingExistingContent)
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
        await setWatchStatus(!isWatched(item), for: item)
    }

    func markWatched(for target: MediaItem? = nil) async {
        await setWatchStatus(true, for: target)
    }

    func markUnwatched(for target: MediaItem? = nil) async {
        await setWatchStatus(false, for: target)
    }

    private func setWatchStatus(_ played: Bool, for target: MediaItem? = nil) async {
        let item = target ?? media.mediaItem
        guard !isUpdatingWatchStatus(for: item) else { return }

        updatingWatchStatusIds.insert(item.id)
        watchActionErrorMessage = nil
        defer { updatingWatchStatusIds.remove(item.id) }

        do {
            try await services.detail.setPlayed(played, itemID: item.id)
            await loadCommonDetails(preservingExistingContent: true)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            watchActionErrorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }

    func toggleWatchlistStatus() async {
        guard !isUpdatingWatchlistStatus else { return }

        isUpdatingWatchlistStatus = true
        defer { isUpdatingWatchlistStatus = false }

        do {
            try await services.detail.setWatchlisted(!isWatchlisted, media: media.mediaItem)
            await loadWatchlistStatus()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    func toggleFavoriteStatus(for target: MediaItem? = nil) async {
        let item = target ?? media.mediaItem
        guard shouldShowFavoriteButton(for: item) else { return }

        let isPrimaryItem = item.id == media.mediaItem.id
        if isPrimaryItem {
            guard !isUpdatingFavoriteStatus else { return }
            isUpdatingFavoriteStatus = true
        }
        guard updatingFavoriteStatusIDs.insert(item.id).inserted else {
            if isPrimaryItem {
                isUpdatingFavoriteStatus = false
            }
            return
        }

        favoriteActionErrorMessage = nil
        defer {
            updatingFavoriteStatusIDs.remove(item.id)
            if isPrimaryItem {
                isUpdatingFavoriteStatus = false
            }
        }

        do {
            let updatedValue = !isFavorite(for: item)
            try await services.favorites.setFavorite(updatedValue, media: item)
            guard !Task.isCancelled else { return }
            favoriteStatusByID[item.id] = updatedValue
            if isPrimaryItem {
                isFavorite = updatedValue
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            favoriteActionErrorMessage = error.localizedDescription
            ErrorReporter.capture(error)
        }
    }

    func imageURL(
        for media: MediaItem,
        width: Int = 320,
        height: Int = 180,
        spoilerProtection: SpoilerProtectionLevel = .off,
    ) -> URL? {
        let path = if media.isSpoilerProtected(at: spoilerProtection) {
            media.spoilerProtectedArtworkPath(at: spoilerProtection)
        } else {
            media.thumbPath ?? media.parentThumbPath ?? media.grandparentThumbPath
        }
        return services.artwork.artworkURL(path: path, width: width, height: height)
    }

    func heroImageURL(spoilerProtection: SpoilerProtectionLevel) -> URL? {
        guard media.mediaItem.isSpoilerProtected(at: spoilerProtection) else {
            return heroImageURL
        }

        let path = media.mediaItem.grandparentArtPath
            ?? parentSeries?.artPath
            ?? media.mediaItem.grandparentThumbPath
        return services.artwork.artworkURL(path: path, width: 1400, height: 800)
    }

    func heroArtworkPath(spoilerProtection: SpoilerProtectionLevel) -> String? {
        if media.mediaItem.isSpoilerProtected(at: spoilerProtection) {
            return media.mediaItem.grandparentArtPath
                ?? parentSeries?.artPath
                ?? media.mediaItem.grandparentThumbPath
        }
        if resolutionMode == .selectedMedia, [.season, .episode].contains(media.type) {
            return media.mediaItem.grandparentArtPath ?? parentSeries?.artPath ?? media.artPath
        }
        return media.artPath ?? media.thumbPath
    }

    @discardableResult
    private func resolveArtwork() -> String? {
        let artPath: String? = if resolutionMode == .selectedMedia, [.season, .episode].contains(media.type) {
            media.mediaItem.grandparentArtPath ?? parentSeries?.artPath ?? media.artPath
        } else {
            media.artPath
        }
        let resolvedPath = artPath ?? media.thumbPath

        heroImageURL = services.artwork.artworkURL(path: artPath, width: 1400, height: 800)
            ?? services.artwork.artworkURL(path: media.thumbPath, width: 1400, height: 800)
        resolveGradient()
        return resolvedPath
    }

    private func resolveGradient() {
        let colors = MediaBackdropGradient.colors(for: .playable(media.mediaItem))
        if colors.count == 4 {
            backdropSourcePath = nil
            backdropGradient = colors
        }
    }

    private func loadBackdropGradient(path: String?) async {
        let providerColors = MediaBackdropGradient.colors(for: .playable(media.mediaItem))
        if providerColors.count == 4 {
            backdropSourcePath = nil
            backdropGradient = providerColors
            return
        }

        guard let path else {
            backdropSourcePath = nil
            backdropGradient = []
            return
        }
        guard backdropSourcePath != path else { return }

        backdropSourcePath = path
        backdropGradient = []

        do {
            guard let resource = try await services.artwork.artwork(
                path: path,
                width: 300,
                height: 169,
            ) else { return }
            let colors = try await ImageCornerColorSampler.colors(from: resource)
            guard !Task.isCancelled, backdropSourcePath == path else { return }
            backdropGradient = colors.count == 4 ? colors : []
        } catch {
            guard !Task.isCancelled, !error.isCancellation, backdropSourcePath == path else { return }
            backdropGradient = []
        }
    }

    private func loadWatchlistStatus() async {
        guard [.movie, .show].contains(media.type) else {
            isWatchlisted = false
            return
        }

        guard services.detail.supportsWatchlist else {
            isWatchlisted = false
            return
        }

        isLoadingWatchlistStatus = true
        defer { isLoadingWatchlistStatus = false }

        do {
            isWatchlisted = try await services.detail.isWatchlisted(media.mediaItem)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            isWatchlisted = false
            ErrorReporter.capture(error)
        }
    }

    private func loadFavoriteStatus() async {
        guard shouldShowFavoriteButton else {
            isFavorite = false
            return
        }

        isLoadingFavoriteStatus = true
        defer { isLoadingFavoriteStatus = false }

        do {
            isFavorite = try await services.favorites.isFavorite(media.mediaItem)
            favoriteStatusByID[media.mediaItem.id] = isFavorite
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            isFavorite = false
            ErrorReporter.capture(error)
        }
    }

    func loadFavoriteStatus(for item: MediaItem) async {
        guard shouldShowFavoriteButton(for: item) else { return }
        guard item.id != media.mediaItem.id else {
            await loadFavoriteStatus()
            return
        }
        guard loadingFavoriteStatusIDs.insert(item.id).inserted else { return }
        defer { loadingFavoriteStatusIDs.remove(item.id) }

        do {
            favoriteStatusByID[item.id] = try await services.favorites.isFavorite(item)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    func isFavorite(for item: MediaItem) -> Bool {
        if item.id == media.mediaItem.id {
            return isFavorite
        }
        return favoriteStatusByID[item.id] ?? item.watchState.isFavorite
    }

    func isLoadingFavoriteStatus(for item: MediaItem) -> Bool {
        item.id == media.mediaItem.id
            ? isLoadingFavoriteStatus
            : loadingFavoriteStatusIDs.contains(item.id)
    }

    func isUpdatingFavoriteStatus(for item: MediaItem) -> Bool {
        updatingFavoriteStatusIDs.contains(item.id)
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
        services.artwork.artworkURL(path: member.thumbPath, width: width, height: height)
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
        return shouldShowPlayFromStartButton(for: target.item)
    }

    func shouldShowPlayFromStartButton(for item: MediaItem) -> Bool {
        hasProgress(for: item)
    }

    var primaryActionRatingKey: String? {
        primaryPlaybackTarget?.item.id
    }

    var primaryActionType: MediaKind? {
        primaryPlaybackTarget?.type
    }

    var primaryActionItem: MediaItem? {
        primaryPlaybackTarget?.item
    }

    var hasTrackSelection: Bool {
        !audioTracks.isEmpty || !subtitleTracks.isEmpty
    }

    var canSearchSubtitles: Bool {
        services.detail.supportsRemoteSubtitleSearch
            && services.authorization.canManageSubtitles
            && (trackRatingKey ?? primaryActionRatingKey) != nil
    }

    var subtitleSearchTitlePlaceholder: String {
        trackPartFile.map { URL(fileURLWithPath: $0).lastPathComponent } ?? media.title
    }

    func hasTrackSelection(for ratingKey: String) -> Bool {
        trackRatingKey == ratingKey && hasTrackSelection
    }

    var selectedAudioTrackTitle: String? {
        selectedTrackTitle(in: audioTracks, id: selectedAudioStreamID)
    }

    var selectedSubtitleTrackTitle: String {
        selectedTrackTitle(in: subtitleTracks, id: selectedSubtitleStreamID)
            ?? String(localized: "player.settings.subtitles.off")
    }

    func selectAudioStream(id: Int) async {
        guard
            let ratingKey = trackRatingKey,
            selectedAudioStreamID != id
        else { return }
        let previousID = selectedAudioStreamID
        selectedAudioStreamID = id
        isUpdatingTracks = true
        trackSelectionErrorMessage = nil
        defer { isUpdatingTracks = false }

        do {
            try await services.detail.selectAudioTrack(id: id, itemID: ratingKey)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                if trackRatingKey == ratingKey {
                    selectedAudioStreamID = previousID
                }
                return
            }
            if trackRatingKey == ratingKey {
                selectedAudioStreamID = previousID
                trackSelectionErrorMessage = error.localizedDescription
            }
            ErrorReporter.capture(error)
        }
    }

    func selectSubtitleStream(id: Int?) async {
        guard
            let ratingKey = trackRatingKey,
            selectedSubtitleStreamID != id
        else { return }
        let previousID = selectedSubtitleStreamID
        selectedSubtitleStreamID = id
        isUpdatingTracks = true
        trackSelectionErrorMessage = nil
        defer { isUpdatingTracks = false }

        do {
            try await services.detail.selectSubtitleTrack(id: id, itemID: ratingKey)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                if trackRatingKey == ratingKey {
                    selectedSubtitleStreamID = previousID
                }
                return
            }
            if trackRatingKey == ratingKey {
                selectedSubtitleStreamID = previousID
                trackSelectionErrorMessage = error.localizedDescription
            }
            ErrorReporter.capture(error)
        }
    }

    func loadTrackSelection(for ratingKey: String) async {
        guard trackRatingKey != ratingKey else { return }
        await loadTrackSelection(for: ratingKey, preservingExistingContent: false)
    }

    func refreshTrackSelectionAfterSubtitleAttachment() async {
        guard let ratingKey = trackRatingKey ?? primaryActionRatingKey else { return }
        await loadTrackSelection(for: ratingKey, preservingExistingContent: false)
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
                type: media.mediaKind,
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

    var favoriteActionTitle: String {
        favoriteActionTitle(for: media.mediaItem)
    }

    var favoriteActionIcon: String {
        favoriteActionIcon(for: media.mediaItem)
    }

    var shouldShowFavoriteButton: Bool {
        shouldShowFavoriteButton(for: media.mediaItem)
    }

    func favoriteActionTitle(for item: MediaItem) -> String {
        isFavorite(for: item)
            ? String(localized: "media.detail.favorite.remove")
            : String(localized: "media.detail.favorite.add")
    }

    func favoriteActionIcon(for item: MediaItem) -> String {
        isFavorite(for: item) ? "star.fill" : "star"
    }

    func shouldShowFavoriteButton(for item: MediaItem) -> Bool {
        services.capabilities.favorites
            && [.movie, .series, .season, .episode].contains(item.type)
    }

    var shouldShowWatchlistButton: Bool {
        services.detail.supportsWatchlist && [.movie, .show].contains(media.type)
            && media.plexGuidID != nil
    }

    var isUpdatingWatchStatus: Bool {
        isUpdatingWatchStatus(for: media.mediaItem)
    }

    func isWatched(_ item: MediaItem) -> Bool {
        item.isFullyWatched
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

    var shouldShowBothWatchActions: Bool {
        shouldShowBothWatchActions(for: media.mediaItem)
    }

    func shouldShowBothWatchActions(for item: MediaItem) -> Bool {
        hasProgress(for: item)
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
        isLoadingSeasons = true
        seasonsErrorMessage = nil
        episodesErrorMessage = nil
        defer { isLoadingSeasons = false }

        do {
            let fetchedSeasons = try await services.detail.seasons(for: media.mediaItem)
            let previousSelectedSeasonId = selectedSeasonId
            seasons = fetchedSeasons

            guard !fetchedSeasons.isEmpty else {
                selectedSeasonId = nil
                episodes = []
                return
            }

            let nextSeasonId = preferredSeasonId(in: fetchedSeasons)
            selectedSeasonId = nextSeasonId
            let shouldPreserveEpisodes = preservingExistingContent
                && previousSelectedSeasonId == nextSeasonId
                && !episodes.isEmpty

            if !shouldPreserveEpisodes {
                episodes = []
            }

            if let seasonId = nextSeasonId {
                await fetchEpisodes(for: seasonId, preservingExistingContent: shouldPreserveEpisodes)
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
        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            guard let season = seasons.first(where: { $0.id == seasonId })
                ?? (media.id == seasonId ? media.mediaItem : nil)
            else { return }
            let fetchedEpisodes = try await services.detail.episodes(
                for: season,
                seriesID: parentSeries?.id ?? media.id,
            )

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

    private func resolveFallbackPlaybackTarget(preservingExistingContent: Bool) async {
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
                let allEpisodes = try await services.detail.allEpisodes(for: media.mediaItem)
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

    private func loadTrackSelection(preservingExistingContent: Bool) async {
        guard let ratingKey = primaryActionRatingKey else {
            clearTrackSelection()
            return
        }

        await loadTrackSelection(for: ratingKey, preservingExistingContent: preservingExistingContent)
    }

    private func loadTrackSelection(
        for ratingKey: String,
        preservingExistingContent: Bool,
    ) async {
        if preservingExistingContent, trackRatingKey == ratingKey, hasTrackSelection {
            return
        }

        requestedTrackRatingKey = ratingKey
        isLoadingTracks = true
        trackSelectionErrorMessage = nil
        defer {
            if requestedTrackRatingKey == ratingKey || requestedTrackRatingKey == nil {
                isLoadingTracks = false
            }
        }

        do {
            let selection = try await services.detail.trackSelection(itemID: ratingKey)
            guard requestedTrackRatingKey == ratingKey else { return }

            trackRatingKey = ratingKey
            trackPartFile = selection.filePath
            audioTracks = selection.audioTracks
            subtitleTracks = selection.subtitleTracks
            selectedAudioStreamID = selection.selectedAudioTrackID
            selectedSubtitleStreamID = selection.selectedSubtitleTrackID
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            guard requestedTrackRatingKey == ratingKey else { return }
            if !preservingExistingContent || trackRatingKey != ratingKey {
                clearTrackSelection()
                trackSelectionErrorMessage = error.localizedDescription
            }
        }
    }

    private func clearTrackSelection() {
        requestedTrackRatingKey = nil
        trackRatingKey = nil
        trackPartFile = nil
        audioTracks = []
        subtitleTracks = []
        selectedAudioStreamID = nil
        selectedSubtitleStreamID = nil
    }

    private func selectedTrackTitle(in tracks: [MediaTrackMetadata], id: Int?) -> String? {
        guard let id, let stream = tracks.first(where: { $0.id == id }) else { return nil }
        return stream.displayTitle.isEmpty ? stream.language ?? stream.codec.uppercased() : stream.displayTitle
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

    private func loadCommonDetails(preservingExistingContent: Bool) async {
        isLoading = true
        errorMessage = nil
        if !preservingExistingContent {
            cast = []
            relatedHubs = []
            onDeckItem = nil
            fallbackPlaybackTarget = nil
        }
        defer { isLoading = false }

        do {
            let target = detailTargetID == media.id
                ? media.mediaItem
                : try await services.detail.mediaItem(id: detailTargetID)
            let content = try await services.detail.details(for: target)
            guard !Task.isCancelled else { return }
            if let mapped = PlayableMediaItem(mediaItem: content.media) {
                media = mapped
            }
            parentSeries = content.parentSeries.flatMap(PlayableMediaItem.init)
            onDeckItem = content.onDeck
            seasons = content.seasons
            episodes = content.episodes
            cast = content.cast
            relatedHubs = content.relatedHubs
            relatedHubsErrorMessage = nil

            switch media.type {
            case .show:
                selectedSeasonId = preferredSeasonId(in: seasons)
                if let selectedSeasonId {
                    await fetchEpisodes(for: selectedSeasonId, preservingExistingContent: preservingExistingContent)
                }
            case .season where resolutionMode == .selectedMedia:
                selectedSeasonId = media.id
            case .movie, .episode, .season:
                selectedSeasonId = nil
            }

            await resolveFallbackPlaybackTarget(preservingExistingContent: preservingExistingContent)
            await loadTrackSelection(preservingExistingContent: preservingExistingContent)
            await loadWatchlistStatus()
            await loadFavoriteStatus()
            let artworkPath = resolveArtwork()
            await loadBackdropGradient(path: artworkPath)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if !preservingExistingContent {
                errorMessage = error.localizedDescription
            }
        }
    }
}
