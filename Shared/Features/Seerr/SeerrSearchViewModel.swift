import Foundation
import Observation

@MainActor
@Observable
final class SeerrSearchViewModel {
    @ObservationIgnored private let store: SeerrStore

    var searchQuery = ""
    var searchResults: [SeerrMedia] = []
    var isSearching = false
    var errorMessage: String?

    init(store: SeerrStore) {
        self.store = store
    }

    var isSearchActive: Bool {
        !searchQuery.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func search() async {
        let trimmedQuery = searchQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let baseURL else { return }

        if trimmedQuery.isEmpty {
            searchResults = []
            isSearching = false
            errorMessage = nil
            return
        }

        isSearching = true
        errorMessage = nil
        defer { isSearching = false }

        do {
            let repository = SeerrDiscoverRepository(baseURL: baseURL)
            let response = try await repository.search(query: trimmedQuery, page: 1)
            guard !Task.isCancelled else { return }
            // Person results aren't handled yet in the UI.
            searchResults = response.results.filter { $0.mediaType != .person }
        } catch is CancellationError {
            return
        } catch {
            if (error as? URLError)?.code == .cancelled {
                return
            }
            errorMessage = String(localized: .init("common.errors.tryAgainLater"))
        }
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }
}
