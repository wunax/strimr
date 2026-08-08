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

    func matches(_ type: PlexItemType) -> Bool {
        switch self {
        case .movies: type == .movie
        case .shows: type == .show || type == .season
        case .episodes: type == .episode
        }
    }

    var requiredSearchTypes: [SearchRepository.SearchType] {
        switch self {
        case .movies: [.movies]
        case .shows, .episodes: [.tv]
        }
    }
}

struct SearchResultSource: Identifiable {
    let serverIdentifier: String
    let serverName: String
    let media: MediaDisplayItem
    let context: PlexAPIContext

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
    private enum SearchEvent {
        case response(SearchResultSource)
        case failure(Error)
        case deadline
    }

    private static let responseDeadline: Duration = .seconds(5)

    var query: String = ""
    var items: [MergedSearchResult] = []
    var isLoading = false
    var errorMessage: String?
    var activeFilters: Set<SearchFilter> = []

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var searchTask: Task<Void, Never>?

    init(
        context: PlexAPIContext,
        sessionManager: SessionManager,
        settingsManager: SettingsManager,
    ) {
        self.context = context
        self.sessionManager = sessionManager
        self.settingsManager = settingsManager
    }

    deinit { searchTask?.cancel() }

    var filteredItems: [MergedSearchResult] {
        guard !activeFilters.isEmpty else { return items }
        return items.filter { result in
            activeFilters.contains { $0.matches(result.media.type) }
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

        let params = SearchRepository.SearchParams(
            query: query.trimmingCharacters(in: .whitespacesAndNewlines),
            searchTypes: resolvedSearchTypes(),
            limit: 100,
        )

        do {
            let sources = if settingsManager.interface.multiServerSearchEnabled {
                try await searchAllServers(params: params)
            } else {
                try await searchCurrentServer(params: params)
            }
            guard !Task.isCancelled else { return }
            items = merge(sources)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            items = []
            errorMessage = error.localizedDescription
        }
    }

    private func searchCurrentServer(
        params: SearchRepository.SearchParams,
    ) async throws -> [SearchResultSource] {
        guard let server = sessionManager.plexServer else {
            throw PlexAPIError.missingConnection
        }
        return try await search(server: server, context: context, params: params)
    }

    private func searchAllServers(
        params: SearchRepository.SearchParams,
    ) async throws -> [SearchResultSource] {
        let servers = try await sessionManager.refreshAvailableServers()
        guard !servers.isEmpty else { return [] }

        var sources: [SearchResultSource] = []
        var failures: [Error] = []
        var remainingServers = servers.count

        await withTaskGroup(of: [SearchEvent].self) { group in
            for server in servers {
                group.addTask { [sessionManager] in
                    do {
                        let serverContext = try await sessionManager.serverContext(
                            for: server.clientIdentifier,
                        )
                        let results = try await self.search(
                            server: server,
                            context: serverContext,
                            params: params,
                        )
                        return results.map(SearchEvent.response)
                    } catch {
                        return [.failure(error)]
                    }
                }
            }
            group.addTask {
                try? await Task.sleep(for: Self.responseDeadline)
                return [.deadline]
            }

            searchLoop: while let events = await group.next() {
                var reachedDeadline = false
                for event in events {
                    switch event {
                    case let .response(source):
                        sources.append(source)
                    case let .failure(error):
                        if !error.isCancellation {
                            failures.append(error)
                        }
                    case .deadline:
                        reachedDeadline = true
                    }
                }
                if reachedDeadline {
                    group.cancelAll()
                    break searchLoop
                }
                remainingServers -= 1
                if remainingServers == 0 {
                    group.cancelAll()
                    break searchLoop
                }
            }
        }

        if sources.isEmpty, let failure = failures.first {
            throw failure
        }
        return sources
    }

    private func search(
        server: PlexCloudResource,
        context: PlexAPIContext,
        params: SearchRepository.SearchParams,
    ) async throws -> [SearchResultSource] {
        let response = try await SearchRepository(context: context).search(params: params)
        return (response.mediaContainer.searchResult ?? [])
            .compactMap(\.metadata)
            .compactMap(MediaDisplayItem.init)
            .map {
                SearchResultSource(
                    serverIdentifier: server.clientIdentifier,
                    serverName: server.name,
                    media: $0,
                    context: context,
                )
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
            if !grouped[key, default: []].contains(where: {
                $0.serverIdentifier == source.serverIdentifier
            }) {
                grouped[key, default: []].append(source)
            }
        }

        let mergedResults: [MergedSearchResult] = order.compactMap { key in
            guard var resultSources = grouped[key], !resultSources.isEmpty else { return nil }
            resultSources.sort { lhs, rhs in
                if lhs.serverIdentifier == sessionManager.plexServer?.clientIdentifier {
                    return true
                }
                if rhs.serverIdentifier == sessionManager.plexServer?.clientIdentifier {
                    return false
                }
                return lhs.serverName.localizedStandardCompare(rhs.serverName) == .orderedAscending
            }
            return MergedSearchResult(id: key, sources: resultSources)
        }
        return mergedResults.sorted { lhs, rhs in
            let titleOrder = lhs.media.primaryLabel.localizedStandardCompare(rhs.media.primaryLabel)
            if titleOrder != .orderedSame {
                return titleOrder == .orderedAscending
            }
            return lhs.id < rhs.id
        }
    }

    private func mergeKey(for media: MediaDisplayItem) -> String {
        if let item = media.playableItem {
            let guid = item.guid.lowercased()
            if !guid.isEmpty {
                return "\(item.type.rawValue):\(guid)"
            }
        }
        let year = media.playableItem?.year.map(String.init) ?? ""
        return "\(media.type.rawValue):\(media.title.folding(options: [.caseInsensitive, .diacriticInsensitive], locale: .current)):\(year)"
    }

    private func resolvedSearchTypes() -> [SearchRepository.SearchType] {
        guard !activeFilters.isEmpty else { return [.movies, .tv] }
        var types = Set<SearchRepository.SearchType>()
        for filter in activeFilters {
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
