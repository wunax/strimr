import Foundation
import Observation
import SwiftUI

@MainActor
@Observable
final class MediaDetailViewModel {
    @ObservationIgnored private let context: PlexAPIContext

    var media: MediaItem
    var onDeckItem: MediaItem?
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

    init(media: MediaItem, context: PlexAPIContext) {
        self.media = media
        self.context = context
        resolveArtwork()
    }

    func loadDetails() async {
        cast = []
        relatedHubs = []
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            errorMessage = String(localized: "errors.selectServer.loadDetails")
            if media.type == .show {
                seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
            }
            relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
            return
        }

        isLoading = true
        errorMessage = nil
        onDeckItem = nil
        watchActionErrorMessage = nil

        do {
            let params = MetadataRepository.PlexMetadataParams(includeOnDeck: true)
            let response = try await metadataRepository.getMetadata(
                ratingKey: media.metadataRatingKey,
                params: params
            )
            if let item = response.mediaContainer.metadata?.first {
                media = MediaItem(plexItem: item)
                cast = castMembers(from: item)
                resolveArtwork()
                resolveGradient()
            }
            onDeckItem = response.mediaContainer.metadata?.first?.onDeck?.metadata.map { MediaItem(plexItem: $0) }
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
        async let relatedHubsTask = loadRelatedHubs()
        await loadSeasonsIfNeeded(forceReload: true)
        await relatedHubsTask
    }

    func loadSeasonsIfNeeded(forceReload: Bool = false) async {
        guard media.type == .show else { return }
        guard forceReload || seasons.isEmpty else { return }
        await fetchSeasons()
    }

    func selectSeason(id: String) async {
        guard selectedSeasonId != id else { return }
        selectedSeasonId = id
        episodes = []
        episodesErrorMessage = nil
        await fetchEpisodes(for: id)
    }

    func toggleWatchStatus(for target: MediaItem? = nil) async {
        let item = target ?? media

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

        heroImageURL = media.artPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        } ?? media.thumbPath.flatMap {
            imageRepository.transcodeImageURL(path: $0, width: 1400, height: 800)
        }
        resolveGradient()
    }

    private func resolveGradient() {
        guard let blur = media.ultraBlurColors else {
            backdropGradient = []
            return
        }

        backdropGradient = [
            Color(hex: blur.topLeft),
            Color(hex: blur.topRight),
            Color(hex: blur.bottomRight),
            Color(hex: blur.bottomLeft),
        ]
    }

    var runtimeText: String? {
        guard let duration = media.duration else { return nil }
        return formatDuration(duration)
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

    func runtimeText(for item: MediaItem) -> String? {
        guard let duration = item.duration else { return nil }
        return formatDuration(duration)
    }

    func castImageURL(for member: CastMember, width: Int = 200, height: Int = 260) -> URL? {
        guard let imageRepository = try? ImageRepository(context: context) else { return nil }
        guard let thumbPath = member.thumbPath else { return nil }
        return imageRepository.transcodeImageURL(path: thumbPath, width: width, height: height)
    }

    var primaryActionTitle: String {
        switch media.type {
        case .movie:
            return hasProgress(for: media)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        case .show:
            return hasProgress(for: onDeckItem)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        case .season, .episode:
            return hasProgress(for: media)
                ? String(localized: "common.actions.resume")
                : String(localized: "common.actions.play")
        }
    }

    var primaryActionDetail: String? {
        switch media.type {
        case .movie:
            return timeLeftText(for: media)
        case .show:
            guard let onDeckItem else { return nil }
            let episodeLabel = seasonEpisodeLabel(for: onDeckItem)
            let timeLeft = timeLeftText(for: onDeckItem)
            if let timeLeft, let episodeLabel {
                return "\(episodeLabel) • \(timeLeft)"
            }
            return episodeLabel ?? timeLeft
        case .season, .episode:
            return timeLeftText(for: media)
        }
    }

    var primaryActionProgress: Double? {
        switch media.type {
        case .movie:
            return progressFraction(for: media)
        case .show:
            guard let onDeckItem else { return nil }
            return progressFraction(for: onDeckItem)
        case .season, .episode:
            return progressFraction(for: media)
        }
    }

    var primaryActionRatingKey: String? {
        switch media.type {
        case .movie:
            return media.id
        case .show:
            return onDeckItem?.id
        case .season, .episode:
            return media.id
        }
    }

    var isWatched: Bool { isWatched(media) }

    func playbackRatingKey() async -> String? {
        if let ratingKey = primaryActionRatingKey {
            return ratingKey
        }

        return await firstGrandchildRatingKey()
    }

    var watchActionTitle: String {
        watchActionTitle(for: media)
    }

    var watchActionIcon: String {
        watchActionIcon(for: media)
    }

    var isUpdatingWatchStatus: Bool {
        isUpdatingWatchStatus(for: media)
    }

    func isWatched(_ item: MediaItem) -> Bool {
        switch item.type {
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

        return String(localized: "media.detail.timeLeft \(formatDuration(remaining))")
    }

    private func seasonEpisodeLabel(for item: MediaItem) -> String? {
        guard let season = item.parentIndex, let episode = item.index else { return nil }
        return String(localized: "media.detail.seasonEpisode \(season) \(episode)")
    }

    private func formatDuration(_ duration: TimeInterval) -> String {
        let minutes = Int(duration / 60)
        let hours = minutes / 60
        let remainingMinutes = minutes % 60
        if hours > 0 {
            return String(localized: "media.detail.duration.hoursMinutes \(hours) \(remainingMinutes)")
        }
        return String(localized: "media.detail.duration.minutes \(remainingMinutes)")
    }

    private func fetchSeasons() async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            seasonsErrorMessage = String(localized: "errors.selectServer.loadSeasons")
            return
        }

        isLoadingSeasons = true
        seasonsErrorMessage = nil
        episodesErrorMessage = nil
        defer { isLoadingSeasons = false }

        do {
            let response = try await metadataRepository.getMetadataChildren(ratingKey: media.metadataRatingKey)
            let fetchedSeasons = (response.mediaContainer.metadata ?? []).map(MediaItem.init)
            seasons = fetchedSeasons
            episodes = []

            guard !fetchedSeasons.isEmpty else {
                selectedSeasonId = nil
                episodes = []
                return
            }

            let nextSeasonId = selectedSeasonId ?? fetchedSeasons.first?.id
            selectedSeasonId = nextSeasonId

            if let seasonId = nextSeasonId {
                await fetchEpisodes(for: seasonId)
            } else {
                episodes = []
            }
        } catch {
            seasons = []
            selectedSeasonId = nil
            episodes = []
            seasonsErrorMessage = error.localizedDescription
        }
    }

    private func fetchEpisodes(for seasonId: String) async {
        guard let metadataRepository = try? MetadataRepository(context: context) else {
            episodesErrorMessage = String(localized: "errors.selectServer.loadEpisodes")
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
            if selectedSeasonId == seasonId {
                episodes = []
                episodesErrorMessage = error.localizedDescription
            }
        }
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
                thumbPath: role.thumb
            )
        }
    }

    private func firstGrandchildRatingKey() async -> String? {
        guard media.type == .show else { return nil }
        guard let metadataRepository = try? MetadataRepository(context: context) else { return nil }

        do {
            let response = try await metadataRepository.getMetadataGrandChildren(ratingKey: media.metadataRatingKey)
            return response.mediaContainer.metadata?.first?.ratingKey
        } catch {
            return nil
        }
    }

    func loadRelatedHubs() async {
        guard let hubRepository = try? HubRepository(context: context) else {
            relatedHubsErrorMessage = String(localized: "errors.selectServer.loadRelatedContent")
            return
        }

        isLoadingRelatedHubs = true
        relatedHubsErrorMessage = nil
        defer { isLoadingRelatedHubs = false }

        do {
            let response = try await hubRepository.getRelatedMediaHubs(ratingKey: media.metadataRatingKey)
            relatedHubs = response.mediaContainer.hub.map(Hub.init)
        } catch {
            relatedHubs = []
            relatedHubsErrorMessage = error.localizedDescription
        }
    }
}

private extension Color {
    init(hex: String) {
        let hex = hex.trimmingCharacters(in: CharacterSet.alphanumerics.inverted)
        var int: UInt64 = 0
        Scanner(string: hex).scanHexInt64(&int)
        let a, r, g, b: UInt64
        switch hex.count {
        case 3: // RGB (12-bit)
            (a, r, g, b) = (255, (int >> 8) * 17, (int >> 4 & 0xF) * 17, (int & 0xF) * 17)
        case 6: // RGB (24-bit)
            (a, r, g, b) = (255, int >> 16, int >> 8 & 0xFF, int & 0xFF)
        case 8: // ARGB (32-bit)
            (a, r, g, b) = (int >> 24, int >> 16 & 0xFF, int >> 8 & 0xFF, int & 0xFF)
        default:
            (a, r, g, b) = (255, 0, 0, 0)
        }

        self.init(
            .sRGB,
            red: Double(r) / 255,
            green: Double(g) / 255,
            blue: Double(b) / 255,
            opacity: Double(a) / 255
        )
    }
}
