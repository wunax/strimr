import Foundation
import Observation

/// A rail of the Explore tab: the watchlist, a fixed row or a hub the source defines.
struct ExploreRail: Identifiable, Hashable {
    enum Content: Hashable {
        case watchlist
        case row(ExploreRowID)
        case hub(String)
    }

    let source: ExploreSourceID
    let content: Content
    let title: String
    let items: [ExploreItem]
    let hasMore: Bool

    var id: String {
        switch content {
        case .watchlist: "\(source.rawValue):watchlist"
        case let .row(row): "\(source.rawValue):row:\(row.rawValue)"
        case let .hub(hub): "\(source.rawValue):hub:\(hub)"
        }
    }
}

@MainActor
@Observable
final class ExploreViewModel {
    static let staleAfter: TimeInterval = 15 * 60
    static let railLimit = 25

    private(set) var rows: [ExploreRowID: ExplorePage] = [:]
    private(set) var hubs: [ExploreHub] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var pendingRequestsCount = 0

    @ObservationIgnored let registry: ExploreSourceRegistry
    @ObservationIgnored private let seerrStore: SeerrStore
    @ObservationIgnored private let now: () -> Date
    @ObservationIgnored private var loadedSourceID: ExploreSourceID?
    @ObservationIgnored private var loadedSource: ObjectIdentifier?
    @ObservationIgnored private var loadedAt: Date?
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private let permissionService = SeerrPermissionService()

    init(registry: ExploreSourceRegistry, seerrStore: SeerrStore, now: @escaping () -> Date = Date.init) {
        self.registry = registry
        self.seerrStore = seerrStore
        self.now = now
    }

    var source: (any ExploreSource)? {
        registry.activeSource
    }

    var rails: [ExploreRail] {
        guard let source else { return [] }
        var rails: [ExploreRail] = []
        if let watchlist = source.watchlist, !watchlist.items.isEmpty {
            rails.append(ExploreRail(
                source: source.id,
                content: .watchlist,
                title: ExploreRowID.watchlist.title,
                items: Array(watchlist.items.prefix(Self.railLimit)),
                hasMore: watchlist.items.count > Self.railLimit,
            ))
        }
        for row in source.rows {
            guard let page = rows[row], !page.items.isEmpty else { continue }
            rails.append(ExploreRail(
                source: source.id,
                content: .row(row),
                title: row.title,
                items: Array(page.items.prefix(Self.railLimit)),
                hasMore: page.hasMore || page.items.count > Self.railLimit,
            ))
        }
        for hub in hubs where !hub.page.items.isEmpty {
            rails.append(ExploreRail(
                source: source.id,
                content: .hub(hub.id),
                title: hub.title,
                items: hub.page.items,
                hasMore: hub.page.hasMore,
            ))
        }
        return rails
    }

    var hasContent: Bool {
        !rails.isEmpty
    }

    var canManageRequests: Bool {
        source?.id == .seerr && permissionService.hasPermission(.manageRequests, user: seerrStore.user)
    }

    var requestsBadgeCount: Int {
        canManageRequests ? pendingRequestsCount : 0
    }

    /// Loads when the source changed, after a failure, or once the rails are stale.
    func loadIfNeeded() async {
        guard let source else {
            reset()
            return
        }
        let isSameSource = loadedSource == ObjectIdentifier(source)
        if isSameSource, let loadedAt, now().timeIntervalSince(loadedAt) < Self.staleAfter, errorMessage == nil {
            return
        }
        if isSameSource, loadTask != nil {
            await loadTask?.value
            return
        }
        await load(preservingContent: isSameSource)
    }

    func reload() async {
        await load(preservingContent: true)
    }

    private func reset() {
        loadTask?.cancel()
        loadTask = nil
        generation += 1
        rows = [:]
        hubs = []
        errorMessage = nil
        isLoading = false
        loadedSource = nil
        loadedSourceID = nil
        loadedAt = nil
    }

    /// Runs in its own task, so leaving the screen mid-load does not show a cancelled request as a failure.
    private func load(preservingContent: Bool) async {
        guard let source else { return }
        if !preservingContent {
            reset()
        }
        loadTask?.cancel()
        generation += 1
        let generation = generation
        loadedSource = ObjectIdentifier(source)
        loadedSourceID = source.id
        let task = Task { [weak self] in
            guard let self else { return }
            await fetch(source, generation: generation)
        }
        loadTask = task
        await task.value
        if self.generation == generation {
            loadTask = nil
        }
    }

    private func fetch(_ source: any ExploreSource, generation: Int) async {
        isLoading = true
        errorMessage = nil
        refreshRequestCount(source)

        var fetchedRows: [ExploreRowID: ExplorePage] = [:]
        var fetchedHubs: [ExploreHub]?
        var failures = 0
        var firstError: Error?

        await withTaskGroup(of: (ExploreRowID?, Result<ExplorePage, Error>?, Result<[ExploreHub], Error>?).self) {
            group in
            for row in source.rows {
                group.addTask { @MainActor in
                    do {
                        return try await (row, .success(source.fetchRow(row, page: 1)), nil)
                    } catch {
                        return (row, .failure(error), nil)
                    }
                }
            }
            if source.hasHubs {
                group.addTask { @MainActor in
                    do {
                        return try await (nil, nil, .success(source.fetchHubs()))
                    } catch {
                        return (nil, nil, .failure(error))
                    }
                }
            }
            if let watchlist = source.watchlist {
                group.addTask { @MainActor in
                    do {
                        try await watchlist.load(force: true)
                        return (nil, nil, nil)
                    } catch {
                        return (.watchlist, .failure(error), nil)
                    }
                }
            }
            for await (row, rowResult, hubResult) in group {
                switch (row, rowResult, hubResult) {
                case let (row?, .success(page)?, _):
                    fetchedRows[row] = page
                case let (_, .failure(error)?, _), let (_, _, .failure(error)?):
                    failures += 1
                    firstError = firstError ?? error
                case let (_, _, .success(hubs)?):
                    fetchedHubs = hubs
                default:
                    break
                }
            }
        }

        guard generation == self.generation, !Task.isCancelled else { return }
        isLoading = false
        rows.merge(fetchedRows) { _, new in new }
        if let fetchedHubs {
            hubs = fetchedHubs
        }
        if let firstError, !firstError.isCancellation, !firstError.isTrackerTransient {
            ErrorReporter.capture(firstError)
        }
        if failures > 0, !hasContent {
            errorMessage = String(localized: "common.errors.tryAgainLater")
        } else {
            loadedAt = now()
        }
    }

    /// The badge count loads apart from the rails, so a slow count never holds them back.
    private func refreshRequestCount(_ source: any ExploreSource) {
        guard source.id == .seerr, canManageRequests,
              let baseURL = seerrStore.baseURLString.flatMap(URL.init(string:))
        else {
            pendingRequestsCount = 0
            return
        }
        Task { [weak self] in
            let count = try? await SeerrRequestRepository(baseURL: baseURL).getRequestCount()
            guard let self, !Task.isCancelled else { return }
            pendingRequestsCount = count?.pending ?? 0
        }
    }
}

@MainActor
@Observable
final class ExploreSearchViewModel {
    var query = ""
    private(set) var results: [ExploreItem] = []
    private(set) var isSearching = false
    private(set) var errorMessage: String?
    private(set) var hasSearched = false

    @ObservationIgnored private let registry: ExploreSourceRegistry

    init(registry: ExploreSourceRegistry) {
        self.registry = registry
    }

    var trimmedQuery: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    var isActive: Bool {
        !trimmedQuery.isEmpty
    }

    /// Searches the active source only; the view runs it again when the source changes.
    func search() async {
        let query = trimmedQuery
        guard !query.isEmpty, let source = registry.activeSource else {
            results = []
            errorMessage = nil
            hasSearched = false
            isSearching = false
            return
        }
        try? await Task.sleep(for: .milliseconds(300))
        guard !Task.isCancelled else { return }
        isSearching = true
        errorMessage = nil
        defer { isSearching = false }
        do {
            let found = try await source.search(query)
            guard !Task.isCancelled else { return }
            results = found
            hasSearched = true
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
            results = []
            hasSearched = true
            errorMessage = String(localized: "common.errors.tryAgainLater")
        }
    }
}

/// The full list behind a rail's See All, capped at three pages.
@MainActor
@Observable
final class ExploreRailViewModel {
    static let maximumPages = 3

    let rail: ExploreRail
    private(set) var items: [ExploreItem]
    private(set) var isLoading = false
    private(set) var errorMessage: String?

    @ObservationIgnored private let source: (any ExploreSource)?
    @ObservationIgnored private var hasLoaded = false

    init(rail: ExploreRail, source: (any ExploreSource)?) {
        self.rail = rail
        self.source = source
        items = rail.items
    }

    func load() async {
        guard !hasLoaded, let source else { return }
        hasLoaded = true
        isLoading = true
        defer { isLoading = false }
        do {
            switch rail.content {
            case .watchlist:
                try await source.watchlist?.load()
                items = source.watchlist?.items ?? items
            case let .row(row):
                var loaded: [ExploreItem] = []
                var seen: Set<String> = []
                for page in 1 ... Self.maximumPages {
                    let result = try await source.fetchRow(row, page: page)
                    loaded += result.items.filter { seen.insert($0.id).inserted }
                    if !result.hasMore {
                        break
                    }
                }
                items = loaded.isEmpty ? items : loaded
            case let .hub(id):
                let page = try await source.fetchHub(id: id)
                items = page.items.isEmpty ? items : page.items
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
            errorMessage = String(localized: "common.errors.tryAgainLater")
        }
    }
}
