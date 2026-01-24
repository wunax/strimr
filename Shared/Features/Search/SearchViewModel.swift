import Foundation
import Observation

enum SearchFilter: String, CaseIterable, Identifiable {
    case movies
    case shows
    case episodes

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .movies:
            String(localized: "search.filter.movies")
        case .shows:
            String(localized: "search.filter.shows")
        case .episodes:
            String(localized: "search.filter.episodes")
        }
    }

    var systemImageName: String {
        switch self {
        case .movies:
            "film.fill"
        case .shows:
            "tv.fill"
        case .episodes:
            "play.rectangle.on.rectangle.fill"
        }
    }

    func matches(_ type: PlexItemType) -> Bool {
        switch self {
        case .movies:
            type == .movie
        case .shows:
            type == .show || type == .season
        case .episodes:
            type == .episode
        }
    }

    var requiredSearchTypes: [SearchRepository.SearchType] {
        switch self {
        case .movies:
            [.movies]
        case .shows, .episodes:
            [.tv]
        }
    }
}

@MainActor
@Observable
final class SearchViewModel {
    var query: String = ""
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var errorMessage: String?
    var activeFilters: Set<SearchFilter> = []

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(context: PlexAPIContext) {
        self.context = context
    }

    deinit {
        searchTask?.cancel()
    }

    var filteredItems: [MediaDisplayItem] {
        guard !activeFilters.isEmpty else { return items }
        return items.filter { item in
            activeFilters.contains { filter in
                filter.matches(item.type)
            }
        }
    }

    var hasQuery: Bool {
        !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    func toggleFilter(_ filter: SearchFilter) {
        if activeFilters.contains(filter) {
            activeFilters.remove(filter)
        } else {
            activeFilters.insert(filter)
        }
        filtersDidChange()
    }

    func queryDidChange() {
        scheduleSearch(immediate: false)
    }

    func filtersDidChange() {
        guard hasQuery else { return }
        scheduleSearch(immediate: true)
    }

    func submitSearch() {
        scheduleSearch(immediate: true)
    }

    private func scheduleSearch(immediate: Bool) {
        searchTask?.cancel()

        guard hasQuery else {
            resetState()
            return
        }

        searchTask = Task { [weak self] in
            if !immediate {
                try? await Task.sleep(nanoseconds: 350_000_000)
            }

            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    private func performSearch() async {
        guard let repository = try? SearchRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.searchLibrary"))
            return
        }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let trimmedQuery = query.trimmingCharacters(in: .whitespacesAndNewlines)
            let params = SearchRepository.SearchParams(
                query: trimmedQuery,
                searchTypes: resolvedSearchTypes(),
                limit: 100,
            )
            let response = try await repository.search(params: params)
            guard !Task.isCancelled else { return }
            let results = response.mediaContainer.searchResult ?? []
            items = results
                .compactMap(\.metadata)
                .compactMap(MediaDisplayItem.init)
        } catch {
            guard !Task.isCancelled else { return }
            ErrorReporter.capture(error)
            items = []
            errorMessage = error.localizedDescription
        }
    }

    private func resolvedSearchTypes() -> [SearchRepository.SearchType] {
        let filters = activeFilters
        guard !filters.isEmpty else { return [.movies, .tv] }

        var types = Set<SearchRepository.SearchType>()
        for filter in filters {
            filter.requiredSearchTypes.forEach { types.insert($0) }
        }

        if types.isEmpty {
            types.insert(.tv)
        }

        return Array(types).sorted { $0.rawValue < $1.rawValue }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
    }
}
