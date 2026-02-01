import Foundation
import Observation

@MainActor
@Observable
final class SeerrPendingRequestsViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let permissionService = SeerrPermissionService()

    var requests: [SeerrRequest] = []
    var mediaDetails: [SeerrRequestMediaKey: SeerrMedia] = [:]
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var isShowingError = false
    var updatingRequestIDs: Set<Int> = []

    private var totalResults = 0
    private let pageSize = 20

    init(store: SeerrStore, session: URLSession = .shared) {
        self.store = store
        self.session = session
    }

    var canManageRequests: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    func load() async {
        guard canManageRequests else { return }
        guard let requestRepository else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await requestRepository.getRequests(take: pageSize, skip: 0, filter: "pending")
            requests = response.results
            totalResults = response.pageInfo.results
            await loadMediaDetails(for: response.results)
        } catch {
            presentError(error)
        }
    }

    func reload() async {
        requests = []
        mediaDetails = [:]
        totalResults = 0
        await load()
    }

    func loadMoreIfNeeded(current request: SeerrRequest) async {
        guard request.id == requests.last?.id else { return }
        guard !isLoadingMore else { return }
        guard requests.count < totalResults else { return }
        guard let requestRepository else { return }

        isLoadingMore = true
        defer { isLoadingMore = false }

        do {
            let response = try await requestRepository.getRequests(
                take: pageSize,
                skip: requests.count,
                filter: "pending",
            )
            requests.append(contentsOf: response.results)
            totalResults = max(totalResults, response.pageInfo.results)
            await loadMediaDetails(for: response.results)
        } catch {
            presentError(error)
        }
    }

    func mediaDetail(for request: SeerrRequest) -> SeerrMedia? {
        guard let key = mediaKey(for: request) else { return nil }
        return mediaDetails[key]
    }

    func approve(_ request: SeerrRequest) async {
        await update(request, status: .approved)
    }

    func decline(_ request: SeerrRequest) async {
        await update(request, status: .declined)
    }

    func isUpdating(_ request: SeerrRequest) -> Bool {
        updatingRequestIDs.contains(request.id)
    }

    func displayName(for request: SeerrRequest) -> String {
        if let name = request.requestedBy?.displayName, !name.isEmpty {
            return name
        }
        if let id = request.requestedBy?.id {
            return String(localized: "seerr.manageRequests.userId \(id)")
        }
        return String(localized: "seerr.manageRequests.unknownUser")
    }

    func requestedAtText(for request: SeerrRequest) -> String? {
        guard let createdAt = request.createdAt else { return nil }
        if let date = parsedDate(from: createdAt) {
            let formatted = SeerrPendingRequestsViewModel.outputDateFormatter.string(from: date)
            return String(localized: "seerr.manageRequests.requestedAt \(formatted)")
        }
        return String(localized: "seerr.manageRequests.requestedAt \(createdAt)")
    }

    func is4kRequest(_ request: SeerrRequest) -> Bool {
        request.is4k ?? false
    }

    func profileName(for request: SeerrRequest) -> String? {
        request.profileName
    }

    func seasonNumbers(for request: SeerrRequest) -> [Int] {
        let seasonNumbers = request.seasons?.compactMap(\.seasonNumber) ?? []
        return seasonNumbers.sorted()
    }

    func mediaTitle(for media: SeerrMedia?) -> String {
        guard let media else { return String(localized: "loading") }
        switch media.mediaType {
        case .movie:
            return media.title ?? media.name ?? ""
        case .tv, .person, .none:
            return media.name ?? media.title ?? ""
        }
    }

    func mediaYear(for media: SeerrMedia?) -> String? {
        guard let media else { return nil }
        let dateString: String? = switch media.mediaType {
        case .movie:
            media.releaseDate
        case .tv:
            media.firstAirDate
        case .person, .none:
            nil
        }
        guard let dateString, dateString.count >= 4 else { return nil }
        return String(dateString.prefix(4))
    }

    private func loadMediaDetails(for requests: [SeerrRequest]) async {
        guard let mediaRepository else { return }

        for request in requests {
            guard let key = mediaKey(for: request) else { continue }
            guard mediaDetails[key] == nil else { continue }
            let tmdbId = key.tmdbId

            do {
                var media: SeerrMedia
                switch key.mediaType {
                case .movie:
                    media = try await mediaRepository.getMovie(id: tmdbId)
                    media.mediaType = .movie
                case .tv:
                    media = try await mediaRepository.getTV(id: tmdbId)
                    media.mediaType = .tv
                case .person:
                    continue
                }
                mediaDetails[key] = media
            } catch {
                continue
            }
        }
    }

    private func update(_ request: SeerrRequest, status: SeerrMediaRequestStatus) async {
        guard let requestRepository else { return }
        guard !updatingRequestIDs.contains(request.id) else { return }

        updatingRequestIDs.insert(request.id)
        defer { updatingRequestIDs.remove(request.id) }

        do {
            try await requestRepository.updateRequestStatus(id: request.id, status: status)
            requests.removeAll { $0.id == request.id }
            totalResults = max(0, totalResults - 1)
        } catch {
            presentError(error)
        }
    }

    private func mediaKey(for request: SeerrRequest) -> SeerrRequestMediaKey? {
        guard let media = request.media,
              let tmdbId = media.tmdbId,
              let mediaType = media.mediaType else { return nil }
        return SeerrRequestMediaKey(tmdbId: tmdbId, mediaType: mediaType)
    }

    private var mediaRepository: SeerrMediaRepository? {
        guard let baseURL else { return nil }
        return SeerrMediaRepository(baseURL: baseURL, session: session)
    }

    private var requestRepository: SeerrRequestRepository? {
        guard let baseURL else { return nil }
        return SeerrRequestRepository(baseURL: baseURL, session: session)
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func parsedDate(from value: String?) -> Date? {
        guard let value else { return nil }
        if let date = SeerrPendingRequestsViewModel.isoFormatterWithFractional.date(from: value) {
            return date
        }
        return SeerrPendingRequestsViewModel.isoFormatter.date(from: value)
    }

    private func presentError(_ error: Error) {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }
        errorMessage = String(localized: .init(key))
        isShowingError = true
    }

    private static let isoFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()

    private static let isoFormatterWithFractional: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter
    }()

    private static let outputDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()
}

struct SeerrRequestMediaKey: Hashable {
    let tmdbId: Int
    let mediaType: SeerrMediaType
}
