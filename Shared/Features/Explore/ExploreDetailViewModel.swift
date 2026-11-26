import Foundation
import Observation

/// A catalog title: its details from its own source, its copies in the libraries, and its watchlist.
@MainActor
@Observable
final class ExploreDetailViewModel {
    enum LibraryState: Equatable {
        case checking
        case found
        case notFound
        case unchecked(Int)
    }

    private(set) var item: ExploreItem
    private(set) var related: [ExploreItem] = []
    private(set) var copies: [MediaCopy] = []
    private(set) var uncheckedServers = 0
    private(set) var isCheckingLibrary = false
    private(set) var hasCheckedLibrary = false
    private(set) var isLoadingDetail = false
    private(set) var hasLoadedDetail = false
    var watchlistErrorMessage: String?

    @ObservationIgnored let registry: ExploreSourceRegistry
    @ObservationIgnored private let seerrStore: SeerrStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(item: ExploreItem, registry: ExploreSourceRegistry, seerrStore: SeerrStore) {
        self.item = item
        self.registry = registry
        self.seerrStore = seerrStore
    }

    /// The Seerr page takes over once Seerr is connected and the title's TMDB id is known.
    var seerrMedia: SeerrMedia? {
        guard seerrStore.isLoggedIn, let tmdbID = item.tmdbID else { return nil }
        return item.seerrMedia ?? SeerrMedia(placeholderID: tmdbID, mediaType: item.kind.seerrType)
    }

    /// Plex rails carry no external ids, so the Seerr page waits for the title's details.
    var needsDetailBeforeSeerr: Bool {
        item.tmdbID == nil && seerrStore.isLoggedIn && !hasLoadedDetail
    }

    var libraryState: LibraryState {
        if isCheckingLibrary || !hasCheckedLibrary {
            return copies.isEmpty ? .checking : .found
        }
        if !copies.isEmpty {
            return .found
        }
        return uncheckedServers > 0 ? .unchecked(uncheckedServers) : .notFound
    }

    /// A Seerr title has no watchlist: no other source's list stands in for it.
    var watchlist: ExploreWatchlist? {
        registry.source(item.source)?.watchlist
    }

    var isOnWatchlist: Bool {
        watchlist?.contains(item.watchlistTarget) ?? false
    }

    var isWatchlistReady: Bool {
        watchlist?.isLoaded == true && watchlist?.isUpdating(item.watchlistTarget) == false
    }

    var watchlistActionTitle: String {
        isOnWatchlist ? String(localized: "explore.watchlist.removeShort") :
            String(localized: "explore.watchlist.addShort")
    }

    var watchlistActionIcon: String {
        isOnWatchlist ? "bookmark.fill" : "bookmark"
    }

    /// Runs once: the catalog page and the Seerr page that replaces it both ask for it.
    func load() async {
        if let loadTask {
            await loadTask.value
            return
        }
        let task = Task { [weak self] in
            guard let self else { return }
            async let watchlistLoad: Void = loadWatchlist()
            await loadDetail()
            await checkLibrary()
            await watchlistLoad
        }
        loadTask = task
        await task.value
    }

    func loadDetail() async {
        guard !hasLoadedDetail, !isLoadingDetail, let source = registry.source(item.source) else {
            hasLoadedDetail = true
            return
        }
        isLoadingDetail = true
        defer {
            isLoadingDetail = false
            hasLoadedDetail = true
        }
        do {
            let detail = try await source.detail(of: item)
            item = item.enriched(with: detail.item)
            related = detail.related
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
        }
    }

    func checkLibrary() async {
        guard !isCheckingLibrary else { return }
        isCheckingLibrary = true
        defer {
            isCheckingLibrary = false
            hasCheckedLibrary = true
        }
        let match = await registry.matcher.match(item)
        guard !Task.isCancelled else { return }
        copies = match.copies
        uncheckedServers = match.uncheckedServers
    }

    /// Seerr's own pages can open from a request that carries no title: the loaded details give one before the
    /// libraries are searched.
    func adopt(_ media: SeerrMedia) {
        guard item.source == .seerr, let updated = Self.item(for: media) else { return }
        item = item.enriched(with: updated)
    }

    func toggleWatchlist() async {
        guard let watchlist else { return }
        let target = item.watchlistTarget
        do {
            try await watchlist.set(!isOnWatchlist, target: target)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
            watchlistErrorMessage = Self.message(for: error)
        }
    }

    private func loadWatchlist() async {
        do {
            try await watchlist?.load()
        } catch {
            guard !Task.isCancelled, !error.isCancellation, !error.isTrackerTransient else { return }
            ErrorReporter.capture(error)
        }
    }

    static func message(for error: Error) -> String {
        if case TrackerAPIError.accountLimit = error {
            return String(localized: "explore.watchlist.error.limit")
        }
        return String(localized: "explore.watchlist.error.generic")
    }
}

extension ExploreDetailViewModel {
    /// Seerr's own pages know a title by its TMDB id only.
    static func item(for media: SeerrMedia) -> ExploreItem? {
        SeerrExploreSource.item(from: media, kind: media.mediaType == .tv ? .show : .movie)
    }
}
