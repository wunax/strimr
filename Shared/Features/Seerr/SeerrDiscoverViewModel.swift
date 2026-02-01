import Foundation
import Observation

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let permissionService = SeerrPermissionService()

    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTV: [SeerrMedia] = []
    var upcomingMovies: [SeerrMedia] = []
    var upcomingTV: [SeerrMedia] = []
    var isLoading = false
    var errorMessage: String?
    var pendingRequestsCount = 0

    init(store: SeerrStore) {
        self.store = store
    }

    var isLoggedIn: Bool {
        store.isLoggedIn
    }

    var hasContent: Bool {
        !trending.isEmpty
            || !popularMovies.isEmpty
            || !popularTV.isEmpty
            || !upcomingMovies.isEmpty
            || !upcomingTV.isEmpty
    }

    var canManageRequests: Bool {
        permissionService.hasPermission(.manageRequests, user: store.user)
    }

    var shouldShowManageRequestsButton: Bool {
        canManageRequests && pendingRequestsCount > 0
    }

    func load() async {
        guard !isLoading else { return }
        guard let baseURL else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repository = SeerrDiscoverRepository(baseURL: baseURL)
            let trendingPage = try await repository.getTrending(page: 1)
            let moviesPage = try await repository.discoverMovies(page: 1)
            let tvPage = try await repository.discoverTV(page: 1)
            let upcomingDate = Self.upcomingDateFormatter.string(from: Date())
            let upcomingMoviesPage = try await repository.discoverMovies(
                page: 1,
                primaryReleaseDateGte: upcomingDate,
            )
            let upcomingTVPage = try await repository.discoverTV(
                page: 1,
                firstAirDateGte: upcomingDate,
            )

            trending = trendingPage.results
            popularMovies = moviesPage.results
            popularTV = tvPage.results
            upcomingMovies = upcomingMoviesPage.results
            upcomingTV = upcomingTVPage.results
        } catch {
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }

        await loadRequestCount()
    }

    func reload() async {
        trending = []
        popularMovies = []
        popularTV = []
        upcomingMovies = []
        upcomingTV = []
        await load()
    }

    func makePendingRequestsViewModel() -> SeerrPendingRequestsViewModel? {
        guard baseURL != nil else { return nil }
        return SeerrPendingRequestsViewModel(store: store)
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func loadRequestCount() async {
        guard canManageRequests else {
            pendingRequestsCount = 0
            return
        }
        guard let baseURL else { return }

        do {
            let repository = SeerrRequestRepository(baseURL: baseURL)
            let count = try await repository.getRequestCount()
            pendingRequestsCount = count.pending
        } catch {
            pendingRequestsCount = 0
        }
    }

    private static let upcomingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
