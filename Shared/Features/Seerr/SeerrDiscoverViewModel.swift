import Foundation
import Observation
import OSLog

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let permissionService = SeerrPermissionService()
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()
    @ObservationIgnored private var fetchTask: Task<Void, Never>?
    @ObservationIgnored private var requestCountTask: Task<Void, Never>?

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

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await fetch(preservingExistingContent: false)
    }

    func reload() async {
        // A running load is joined as it is, so the rows on screen stay until it finishes.
        if fetchTask == nil {
            trending = []
            popularMovies = []
            popularTV = []
            upcomingMovies = []
            upcomingTV = []
        }
        await fetch(preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        var now = now
        if let fetchTask {
            // A load that is still running only needs a follow-up when it fails.
            await fetchTask.value
            guard isShowingFailure else { return }
            // The wait can be long, so the retry is timed from when it starts.
            now = Date()
        }
        // A failed load leaves the screen empty, so it is retried without waiting for the debounce.
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading, ignoringDebounce: isShowingFailure) else {
            return
        }
        await fetch(preservingExistingContent: true)
    }

    private var isShowingFailure: Bool {
        errorMessage != nil && !hasContent
    }

    /// Runs in its own task: the view cancels its `.task` when the screen is left and may cancel a pull to refresh
    /// when it redraws, and a cancelled request would otherwise be shown as a failed load.
    private func fetch(preservingExistingContent: Bool) async {
        if let fetchTask {
            await fetchTask.value
            return
        }

        let task = Task { [weak self] in
            guard let self else { return }
            await performFetch(preservingExistingContent: preservingExistingContent)
            fetchTask = nil
        }
        fetchTask = task
        await task.value
    }

    private func performFetch(preservingExistingContent: Bool) async {
        guard let baseURL else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        refreshRequestCount()

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
            // The description of a transport error can contain the server address, so only domain and code are public.
            let nsError = error as NSError
            let details = String(describing: error)
            Self.logger.error(
                "Load failed: \(nsError.domain, privacy: .public) \(nsError.code) \(details, privacy: .private)",
            )
            handleLoadError(preservingExistingContent: preservingExistingContent)
        }
    }

    var requestsBadgeCount: Int {
        canManageRequests ? pendingRequestsCount : 0
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    /// The badge count loads on its own task: a slow count request does not hold back the rows, and a load that is
    /// still running never has its rows or its error on screen.
    private func refreshRequestCount() {
        requestCountTask?.cancel()
        requestCountTask = Task { [weak self] in
            await self?.loadRequestCount()
        }
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
            guard !Task.isCancelled else { return }
            pendingRequestsCount = count.pending
        } catch {
            guard !Task.isCancelled else { return }
            pendingRequestsCount = 0
        }
    }

    private static let logger = Logger(subsystem: "Strimr", category: "SeerrDiscover")

    private static let upcomingDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()

    private func handleLoadError(preservingExistingContent: Bool) {
        if preservingExistingContent, hasContent {
            errorMessage = nil
        } else {
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }
    }
}
