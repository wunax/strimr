import Foundation
import Observation

@MainActor
@Observable
final class SeerrManageRequestsViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let session: URLSession

    var media: SeerrMedia
    var isShowingError = false
    var errorMessage: String?
    var updatingRequestIDs: Set<Int> = []
    var statusOverrides: [Int: SeerrMediaRequestStatus] = [:]

    init(media: SeerrMedia, store: SeerrStore, session: URLSession = .shared) {
        self.media = media
        self.store = store
        self.session = session
    }

    var pendingRequests: [SeerrRequest] {
        let requests = media.mediaInfo?.requests ?? []
        return requests
            .filter { request in
                let status = statusOverrides[request.id] ?? request.status
                return status == .pending
            }
            .sorted { lhs, rhs in
                guard let leftDate = parsedDate(from: lhs.createdAt),
                      let rightDate = parsedDate(from: rhs.createdAt)
                else {
                    return lhs.id < rhs.id
                }
                return leftDate < rightDate
            }
    }

    var isTV: Bool {
        media.mediaType == .tv
    }

    func isUpdating(_ request: SeerrRequest) -> Bool {
        updatingRequestIDs.contains(request.id)
    }

    func approve(_ request: SeerrRequest) async {
        await update(request, status: .approved)
    }

    func decline(_ request: SeerrRequest) async {
        await update(request, status: .declined)
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
            let formatted = SeerrManageRequestsViewModel.outputDateFormatter.string(from: date)
            return String(localized: "seerr.manageRequests.requestedAt \(formatted)")
        }
        return String(localized: "seerr.manageRequests.requestedAt \(createdAt)")
    }

    func avatarURL(for user: SeerrUser?) -> URL? {
        guard let avatar = user?.avatar, !avatar.isEmpty else { return nil }
        if let url = URL(string: avatar), url.scheme != nil {
            return url
        }
        guard let baseURL else { return nil }
        let path = avatar.hasPrefix("/") ? String(avatar.dropFirst()) : avatar
        return baseURL.appendingPathComponent(path)
    }

    func seasonNumbers(for request: SeerrRequest) -> [Int] {
        guard isTV else { return [] }
        let seasonNumbers = request.seasons?.compactMap(\.seasonNumber) ?? []
        if seasonNumbers.isEmpty {
            return []
        }
        return seasonNumbers.sorted()
    }

    func is4kRequest(_ request: SeerrRequest) -> Bool {
        request.is4k ?? false
    }

    private func update(_ request: SeerrRequest, status: SeerrMediaRequestStatus) async {
        guard let requestRepository else { return }
        guard !updatingRequestIDs.contains(request.id) else { return }

        updatingRequestIDs.insert(request.id)
        defer { updatingRequestIDs.remove(request.id) }

        do {
            try await requestRepository.updateRequestStatus(id: request.id, status: status)
            statusOverrides[request.id] = status
        } catch {
            presentError(error)
        }
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
        if let date = SeerrManageRequestsViewModel.isoFormatterWithFractional.date(from: value) {
            return date
        }
        return SeerrManageRequestsViewModel.isoFormatter.date(from: value)
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
