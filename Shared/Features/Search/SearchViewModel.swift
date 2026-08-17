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
    let serverIdentifier: String
    let serverName: String
    let media: MediaDisplayItem
    let services: MediaServices

    var id: String {
        "\(serverIdentifier):\(media.id)"
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

@MainActor
@Observable
final class SearchViewModel {
    var query = ""
    var items: [MergedSearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var activeFilters: Set<SearchFilter> = []

    @ObservationIgnored private let services: MediaServices
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(services: MediaServices, settingsManager: SettingsManager) {
        self.services = services
        self.settingsManager = settingsManager
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
        do {
            let values = try await services.search.search(
                query: query.trimmingCharacters(in: .whitespacesAndNewlines),
                kinds: resolvedKinds(),
                searchesAllServers: services.capabilities.multiServerSearch
                    && settingsManager.interface.multiServerSearchEnabled,
            )
            guard !Task.isCancelled else { return }
            items = merge(values.map {
                SearchResultSource(
                    serverIdentifier: $0.serverIdentifier,
                    serverName: $0.serverName,
                    media: $0.media,
                    services: $0.services,
                )
            })
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            resetState(error: error.localizedDescription)
        }
    }

    private func merge(_ sources: [SearchResultSource]) -> [MergedSearchResult] {
        var order: [String] = []
        var grouped: [String: [SearchResultSource]] = [:]
        for source in sources {
            let key = mergeKey(for: source.media)
            if grouped[key] == nil {
                order.append(key)
            }
            if !grouped[key, default: []].contains(where: { $0.serverIdentifier == source.serverIdentifier }) {
                grouped[key, default: []].append(source)
            }
        }
        return order.compactMap { key in
            guard var resultSources = grouped[key], !resultSources.isEmpty else { return nil }
            resultSources.sort { $0.serverName.localizedStandardCompare($1.serverName) == .orderedAscending }
            return MergedSearchResult(id: key, sources: resultSources)
        }.sorted {
            $0.media.primaryLabel.localizedStandardCompare($1.media.primaryLabel) == .orderedAscending
        }
    }

    private func mergeKey(for media: MediaDisplayItem) -> String {
        if let item = media.playableItem, !item.guid.isEmpty {
            return "\(item.kind.rawValue):\(item.guid.lowercased())"
        }
        let year = media.playableItem?.year.map(String.init) ?? ""
        return "\(media.type.rawValue):\(media.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)):\(year)"
    }

    private func resolvedKinds() -> Set<MediaKind> {
        activeFilters.reduce(into: Set<MediaKind>()) { result, filter in
            result.formUnion(filter.kinds)
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
    }
}
