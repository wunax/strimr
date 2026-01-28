import Foundation
import Observation

@MainActor
@Observable
final class SeerrDiscoverViewModel {
    @ObservationIgnored private let store: SeerrStore

    var trending: [SeerrMedia] = []
    var popularMovies: [SeerrMedia] = []
    var popularTV: [SeerrMedia] = []
    var isLoading = false
    var errorMessage: String?

    init(store: SeerrStore) {
        self.store = store
    }

    var isLoggedIn: Bool {
        store.isLoggedIn
    }

    var hasContent: Bool {
        !trending.isEmpty || !popularMovies.isEmpty || !popularTV.isEmpty
    }

    func load() async {
        guard !isLoading else { return }
        guard let baseURL else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let repository = SeerrDiscoverRepository(baseURL: baseURL)
            async let trendingResponse = repository.getTrending(page: 1)
            async let popularMoviesResponse = repository.discoverMovies(page: 1)
            async let popularTVResponse = repository.discoverTV(page: 1)

            let (trendingPage, moviesPage, tvPage) = try await (
                trendingResponse,
                popularMoviesResponse,
                popularTVResponse
            )

            trending = trendingPage.results
            popularMovies = moviesPage.results
            popularTV = tvPage.results
        } catch {
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }
    }

    func reload() async {
        trending = []
        popularMovies = []
        popularTV = []
        await load()
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }
}
