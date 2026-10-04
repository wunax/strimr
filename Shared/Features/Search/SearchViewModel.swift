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
        case .movies: String(localized: "search.filter.movies")
        case .shows: String(localized: "search.filter.shows")
        case .episodes: String(localized: "search.filter.episodes")
        }
    }

    var systemImageName: String {
        switch self {
        case .movies: "film.fill"
        case .shows: "tv.fill"
        case .episodes: "play.rectangle.on.rectangle.fill"
        }
    }

    func matches(_ kind: MediaKind) -> Bool {
        switch self {
        case .movies: kind == .movie
        case .shows: kind == .series || kind == .season
        case .episodes: kind == .episode
        }
    }

    var kinds: Set<MediaKind> {
        switch self {
        case .movies: [.movie]
        case .shows: [.series, .season]
        case .episodes: [.episode]
        }
    }
}

struct SearchResultSource: Identifiable {
    let server: ServerIdentity
    let serverName: String
    let media: MediaDisplayItem

    var id: String {
        "\(server.stableKey):\(media.id)"
    }
}

struct MergedSearchResult: Identifiable {
    let id: String
    var sources: [SearchResultSource]

    var primarySource: SearchResultSource {
        sources[0]
    }

    var media: MediaDisplayItem {
        primarySource.media
    }

    var serverNames: [String] {
        sources.map(\.serverName)
    }
}

enum SearchRanking {
    /// Copies of the same title on several servers become one result (§5.6); results are then ordered by relevance
    /// (exact match, prefix, contains), then by year, newest first, the title only breaking ties.
    static func merge(_ sources: [SearchResultSource], query: String) -> [MergedSearchResult] {
        let groups = MediaMatching.group(sources) { source in
            source.media.playableItem?.matchDescriptor
                ?? MediaMatchDescriptor(kind: .other, guid: nil, externalIDs: ExternalIDs())
        }
        let results = groups.map { group in
            var seen = Set<String>()
            let unique = group.filter { seen.insert($0.id).inserted }
            return MergedSearchResult(id: unique[0].id, sources: unique)
        }
        let normalizedQuery = normalize(query)
        return results.enumerated().sorted { lhs, rhs in
            let left = lhs.element.media
            let right = rhs.element.media
            let leftRelevance = relevance(of: left.primaryLabel, query: normalizedQuery)
            let rightRelevance = relevance(of: right.primaryLabel, query: normalizedQuery)
            if leftRelevance != rightRelevance {
                return leftRelevance < rightRelevance
            }
            let leftYear = left.playableItem?.year ?? 0
            let rightYear = right.playableItem?.year ?? 0
            if leftYear != rightYear {
                return leftYear > rightYear
            }
            let order = left.primaryLabel.localizedStandardCompare(right.primaryLabel)
            return order == .orderedSame ? lhs.offset < rhs.offset : order == .orderedAscending
        }.map(\.element)
    }

    /// 0: exact, 1: prefix, 2: contains, 3: other.
    static func relevance(of title: String, query: String) -> Int {
        let title = normalize(title)
        guard !query.isEmpty else { return 3 }
        if title == query {
            return 0
        }
        if title.hasPrefix(query) {
            return 1
        }
        if title.contains(query) {
            return 2
        }
        return 3
    }

    static func normalize(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Search over every enabled server of the profile, in parallel. Servers that fail are listed so the page can say
/// they did not answer; the other results are shown anyway.
@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var items: [MergedSearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var unavailableServerNames: [String] = []
    var activeFilters: Set<SearchFilter> = []

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(sessionManager: SessionManager) {
        self.sessionManager = sessionManager
    }

    deinit { searchTask?.cancel() }

    var filteredItems: [MergedSearchResult] {
        guard !activeFilters.isEmpty else { return items }
        return items.filter { result in
            activeFilters.contains { $0.matches(result.media.playableItem?.kind ?? .unknown) }
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
                try? await Task.sleep(for: .milliseconds(350))
            }
            guard !Task.isCancelled else { return }
            await self?.performSearch()
        }
    }

    private func performSearch() async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        let query = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kinds = resolvedKinds()
        let registry = sessionManager.registry
        let sessions = registry.sessions
        #if os(tvOS)
            let targets = sessions
        #else
            // Unreachable servers still search their cached items.
            let targets = sessions.map { session in
                var session = session
                if session.isEnabled, session.services != nil, session.status == .unreachable {
                    session.status = .ready
                }
                return session
            }
        #endif
        let result = await sessionManager.aggregation.fanOut(servers: targets) { services in
            try await services.search.search(query: query, kinds: kinds)
        }
        guard !Task.isCancelled else { return }
        let names = Dictionary(sessions.map { ($0.identity, $0.name) }, uniquingKeysWith: { first, _ in first })
        let sources = targets.map(\.identity).flatMap { server in
            (result.value[server] ?? []).map {
                SearchResultSource(server: server, serverName: names[server] ?? server.id, media: $0)
            }
        }
        items = SearchRanking.merge(sources, query: query)
        unavailableServerNames = result.failed.compactMap { names[$0] }.sorted()
        if items.isEmpty, result.succeeded.isEmpty, !result.failed.isEmpty {
            errorMessage = String(localized: "search.error.unavailable")
        }
    }

    private func resolvedKinds() -> Set<MediaKind> {
        activeFilters.reduce(into: Set<MediaKind>()) { result, filter in
            result.formUnion(filter.kinds)
        }
    }

    private func resetState() {
        items = []
        errorMessage = nil
        unavailableServerNames = []
        isLoading = false
    }
}
