import Foundation
import Observation
import SwiftUI

enum SeerrSeasonAvailabilityBadge: Hashable {
    case media(SeerrMediaStatus)
    case request(SeerrMediaRequestStatus)
}

@MainActor
@Observable
final class SeerrMediaDetailViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private var backdropSourceURL: URL?

    var media: SeerrMedia
    var isLoading = false
    var errorMessage: String?
    var backdropGradient: [Color] = []

    var seasons: [SeerrSeason] = []
    var episodes: [SeerrEpisode] = []
    var selectedSeasonNumber: Int?
    var isLoadingSeasons = false
    var isLoadingEpisodes = false
    var seasonsErrorMessage: String?
    var episodesErrorMessage: String?

    init(media: SeerrMedia, store: SeerrStore, session: URLSession = .shared) {
        self.media = media
        self.store = store
        self.session = session
        refreshFromMedia()
    }

    var heroImageURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 1400)
    }

    private var backdropGradientURL: URL? {
        TMDBImageService.backdropURL(path: media.backdropPath, width: 300)
    }

    var displayTitle: String {
        switch media.mediaType {
        case .movie:
            media.title ?? media.name ?? ""
        case .tv, .person:
            media.name ?? media.title ?? ""
        case .none:
            media.title ?? media.name ?? ""
        }
    }

    var secondaryLabel: String? {
        yearText
    }

    var tertiaryLabel: String? {
        guard media.mediaType == .tv else { return nil }
        return seasonCountText
    }

    var yearText: String? {
        switch media.mediaType {
        case .movie:
            year(from: media.releaseDate)
        case .tv:
            year(from: media.firstAirDate)
        case .person, .none:
            nil
        }
    }

    var runtimeText: String? {
        guard let runtime = media.runtime, runtime > 0 else { return nil }
        return TimeInterval(runtime * 60).mediaDurationText()
    }

    var ratingText: String? {
        guard let voteAverage = media.voteAverage, voteAverage > 0 else { return nil }
        return String(format: "%.1f", locale: .current, voteAverage)
    }

    var seasonCountText: String? {
        let count = media.numberOfSeasons ?? seasons.count
        guard count > 0 else { return nil }
        return String(localized: "media.labels.seasonsCount \(count)")
    }

    var episodesCountText: String? {
        let count = media.numberOfEpisodes ?? 0
        guard count > 0 else { return nil }
        return String(localized: "media.labels.countEpisode \(count)")
    }

    var genres: [String] {
        media.genres?.compactMap(\.name).filter { !$0.isEmpty } ?? []
    }

    var cast: [SeerrCastMember] {
        let cast = media.credits?.cast ?? []
        return cast.sorted { ($0.order ?? 0) < ($1.order ?? 0) }
    }

    var creatorsText: String? {
        let names = media.createdBy?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var productionText: String? {
        let names = media.productionCompanies?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var countriesText: String? {
        let names = media.productionCountries?.compactMap(\.name).filter { !$0.isEmpty } ?? []
        guard !names.isEmpty else { return nil }
        return names.joined(separator: ", ")
    }

    var selectedSeason: SeerrSeason? {
        guard let selectedSeasonNumber else { return nil }
        return seasons.first { $0.seasonNumber == selectedSeasonNumber }
    }

    var episodeCountDisplay: Int {
        if !episodes.isEmpty {
            return episodes.count
        }
        return selectedSeason?.episodeCount ?? 0
    }

    func loadDetails() async {
        guard !isLoading else { return }
        guard let baseURL else {
            errorMessage = String(localized: "integrations.seerr.error.invalidURL")
            return
        }

        isLoading = true
        if media.mediaType == .tv {
            isLoadingSeasons = true
        }
        errorMessage = nil
        seasonsErrorMessage = nil
        defer {
            isLoading = false
            isLoadingSeasons = false
        }

        do {
            let repository = SeerrMediaRepository(baseURL: baseURL)
            switch media.mediaType {
            case .movie:
                media = try await repository.getMovie(id: media.id)
                media.mediaType = .movie
            case .tv:
                media = try await repository.getTV(id: media.id)
                media.mediaType = .tv
            case .person, .none:
                break
            }
            refreshFromMedia()
            await loadBackdropGradient()
            if media.mediaType == .tv {
                await loadSeasonIfNeeded()
            }
        } catch {
            let message = errorMessage(for: error)
            errorMessage = message
            seasonsErrorMessage = message
        }
    }

    func selectSeason(number: Int) async {
        guard selectedSeasonNumber != number else { return }
        selectedSeasonNumber = number
        episodes = []
        episodesErrorMessage = nil
        await loadSeason(number: number)
    }

    func seasonTitle(for season: SeerrSeason) -> String {
        if let name = season.name, !name.isEmpty {
            return name
        }
        if let number = season.seasonNumber {
            return String(localized: "media.detail.season") + " \(number)"
        }
        return String(localized: "media.detail.season")
    }

    func episodeLabel(for episode: SeerrEpisode) -> String? {
        let seasonNumber = episode.seasonNumber ?? selectedSeasonNumber
        guard let seasonNumber, let episodeNumber = episode.episodeNumber else { return nil }
        return String(localized: "media.labels.seasonEpisode \(seasonNumber) \(episodeNumber)")
    }

    func episodeAirDateText(for episode: SeerrEpisode) -> String? {
        formattedDate(from: episode.airDate)
    }

    func episodeImageURL(for episode: SeerrEpisode, width: CGFloat) -> URL? {
        TMDBImageService.backdropURL(path: episode.stillPath, width: width)
    }

    func seasonAvailabilityBadge(for season: SeerrSeason) -> SeerrSeasonAvailabilityBadge? {
        guard let seasonNumber = season.seasonNumber else { return nil }
        // Prefer direct media info when the season availability is known.
        if let seasonStatus = media.mediaInfo?.seasons?.first(where: { $0.seasonNumber == seasonNumber })?.status,
           seasonStatus != .unknown {
            return .media(seasonStatus)
        }

        // Fall back to request data for the season, ignoring declined/completed requests (classic only, not 4K).
        let matchingStatuses = media.mediaInfo?.requests?.compactMap { request -> SeerrMediaRequestStatus? in
            guard request.is4k != true else { return nil }
            guard let requestStatus = request.status, requestStatus != .declined, requestStatus != .completed else {
                return nil
            }
            guard let requestSeasons = request.seasons else { return requestStatus }
            guard requestSeasons.contains(where: { $0.seasonNumber == seasonNumber }) else { return nil }
            if let seasonStatus = requestSeasons.first(where: { $0.seasonNumber == seasonNumber })?.status,
               seasonStatus != .declined, seasonStatus != .completed {
                return seasonStatus
            }
            return requestStatus
        } ?? []

        // Pick the highest-priority request badge we support.
        let requestBadgePriority: [SeerrMediaRequestStatus] = [.pending, .approved]
        if let status = requestBadgePriority.first(where: { matchingStatuses.contains($0) }) {
            return .request(status)
        }
        return nil
    }

    func castImageURL(for member: SeerrCastMember, width: CGFloat, height: CGFloat) -> URL? {
        TMDBImageService.profileURL(path: member.profilePath, width: width, height: height)
    }

    private func refreshFromMedia() {
        seasons = (media.seasons ?? []).filter { $0.seasonNumber != nil }
        if selectedSeasonNumber == nil {
            selectedSeasonNumber = defaultSeasonNumber
        }
    }

    private var defaultSeasonNumber: Int? {
        seasons.first(where: { ($0.seasonNumber ?? 0) > 0 })?.seasonNumber ?? seasons.first?.seasonNumber
    }

    private func loadSeasonIfNeeded() async {
        guard let selectedSeasonNumber else { return }
        if episodes.isEmpty {
            await loadSeason(number: selectedSeasonNumber)
        }
    }

    private func loadSeason(number: Int) async {
        guard let baseURL else { return }
        guard media.mediaType == .tv else { return }

        isLoadingEpisodes = true
        episodesErrorMessage = nil
        defer { isLoadingEpisodes = false }

        do {
            let repository = SeerrMediaRepository(baseURL: baseURL)
            let season = try await repository.getTVSeason(id: media.id, seasonNumber: number)
            episodes = season.episodes ?? []
        } catch {
            episodesErrorMessage = errorMessage(for: error)
        }
    }

    private func loadBackdropGradient() async {
        guard let url = backdropGradientURL else {
            backdropGradient = []
            return
        }
        guard backdropSourceURL != url else { return }
        backdropSourceURL = url

        do {
            let (data, _) = try await session.data(from: url)
            let colors = ImageCornerColorSampler.colors(from: data)
            if colors.count == 4 {
                backdropGradient = colors
            }
        } catch {
            backdropGradient = []
        }
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func year(from dateString: String?) -> String? {
        guard let dateString, dateString.count >= 4 else { return nil }
        return String(dateString.prefix(4))
    }

    private func formattedDate(from dateString: String?) -> String? {
        guard let dateString else { return nil }
        guard let date = SeerrMediaDetailViewModel.inputDateFormatter.date(from: dateString) else {
            return dateString
        }
        return SeerrMediaDetailViewModel.outputDateFormatter.string(from: date)
    }

    private func errorMessage(for error: Error) -> String {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }
        return String(localized: .init(key))
    }

    private static let inputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .none
        return formatter
    }()
}
