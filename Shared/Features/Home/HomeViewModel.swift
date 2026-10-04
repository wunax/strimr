import Foundation
import Observation

/// Home of the active profile, aggregated over its servers. Each server is loaded on its own: a failing server is
/// simply absent and a server that comes online later only adds its own rows.
@MainActor
@Observable
final class HomeViewModel {
    private(set) var availableRows: [HomeRow] = []
    var isLoading = false
    var errorMessage: String?

    private var rowsByServer: [ServerIdentity: [HomeRow]] = [:]
    private(set) var loadedServers: Set<ServerIdentity> = []

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(sessionManager: SessionManager, settingsManager: SettingsManager) {
        self.sessionManager = sessionManager
        self.settingsManager = settingsManager
    }

    private var registry: ServerRegistry {
        sessionManager.registry
    }

    private var profileID: String {
        sessionManager.activeProfile?.id ?? ""
    }

    // MARK: - Rows

    var orderedRowsForEditing: [HomeRow] {
        let preferences = settingsManager.homeRowPreferences(profileID: profileID)
        return pinningOfflineDownloads(preferences.orderedRows(from: availableRows), preferences: preferences)
    }

    var rows: [HomeRow] {
        let preferences = settingsManager.homeRowPreferences(profileID: profileID)
        return pinningOfflineDownloads(preferences.visibleRows(from: availableRows), preferences: preferences)
    }

    var showsServerNames: Bool {
        registry.hasMultipleServers
    }

    /// The offline "Downloads" rows go first unless the user placed them somewhere else.
    private func pinningOfflineDownloads(_ rows: [HomeRow], preferences: HomeRowPreferences) -> [HomeRow] {
        #if os(tvOS)
            rows
        #else
            let placed = Set(preferences.orderedRowIDs)
            let pinned = rows.filter { CachedHomeService.isOfflineDownloadsRow($0) && !placed.contains($0.id) }
            guard !pinned.isEmpty else { return rows }
            let pinnedIDs = Set(pinned.map(\.id))
            return pinned + rows.filter { !pinnedIDs.contains($0.id) }
        #endif
    }

    func isRowVisible(_ rowID: String) -> Bool {
        !settingsManager.homeRowPreferences(profileID: profileID).hiddenRowIDs.contains(rowID)
    }

    func setRowVisible(_ rowID: String, visible: Bool) {
        settingsManager.setHomeRowVisibility(rowID, visible: visible, profileID: profileID)
    }

    func moveRow(at index: Int, by offset: Int) {
        var rowIDs = orderedRowsForEditing.map(\.id)
        let destination = index + offset
        guard rowIDs.indices.contains(index), rowIDs.indices.contains(destination) else { return }
        let rowID = rowIDs.remove(at: index)
        rowIDs.insert(rowID, at: destination)
        settingsManager.setHomeRowOrder(rowIDs, profileID: profileID)
    }

    func resetRowPreferences() {
        settingsManager.resetHomeRows(profileID: profileID)
    }

    var hasContent: Bool {
        rows.contains { $0.hub.hasItems }
    }

    // MARK: - Loading

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    /// Reloads every server.
    func reload() async {
        await reload(servers: nil, preservingExistingContent: false)
    }

    /// Automatic refresh only retries the servers that have not answered yet.
    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        let pending = Set(registry.enabledSessions.map(\.identity)).subtracting(loadedServers)
        guard !pending.isEmpty else { return }
        await reload(servers: pending, preservingExistingContent: true)
    }

    /// After playback, only the item's server is reloaded to update Reprendre and Next Up.
    func refresh(server: ServerIdentity) async {
        await reload(servers: [server], preservingExistingContent: true)
    }

    /// Merges servers that became ready since the last load and drops the rows of disabled servers, without reloading
    /// the others.
    func syncServers() async {
        let ready = registry.readyServers
        // A disabled server, or an unreachable one while others answer, leaves the home; its row preferences stay.
        let kept = ready.isEmpty ? Set(registry.enabledSessions.map(\.identity)) : ready
        let removed = Set(rowsByServer.keys).subtracting(kept)
        if !removed.isEmpty {
            for server in removed {
                rowsByServer[server] = nil
                cachedOnlyServers.remove(server)
            }
            loadedServers.subtract(removed)
            rebuild()
        }
        let arrived = ready.subtracting(loadedServers)
        guard refreshGate.hasStartedInitialLoad, !arrived.isEmpty else { return }
        await reload(servers: arrived, preservingExistingContent: true)
    }

    private func reload(servers: Set<ServerIdentity>?, preservingExistingContent: Bool) async {
        if servers == nil {
            loadTask?.cancel()
        }
        let task = Task { [weak self] in
            guard let self else { return }
            await fetch(servers: servers, preservingExistingContent: preservingExistingContent)
        }
        if servers == nil {
            loadTask = task
        }
        await task.value
    }

    private func fetch(servers: Set<ServerIdentity>?, preservingExistingContent: Bool) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        #if !os(tvOS)
            if availableRows.isEmpty {
                showCachedHome()
            }
        #endif

        let sessions = registry.sessions.filter { servers?.contains($0.identity) ?? true }
        let includesPlaylists = settingsManager.interface.displayPlaylists
        let hidden = settingsManager.libraryPreferences(profileID: profileID).hiddenLibraries
        let result = await sessionManager.aggregation.fanOut(servers: sessions) { services in
            let hiddenIDs = Set(hidden.filter { $0.server == services.identity }.map(\.libraryID))
            return try await services.home.loadHome(hiddenLibraryIDs: hiddenIDs, includesPlaylists: includesPlaylists)
        }
        guard !Task.isCancelled else { return }

        for (server, content) in result.value {
            rowsByServer[server] = content.rows
        }
        cachedOnlyServers.subtract(result.succeeded)
        loadedServers.formUnion(result.succeeded)
        if servers == nil, !result.succeeded.isEmpty {
            // Servers that did not answer are absent from the home; their row preferences are untouched.
            for server in Set(rowsByServer.keys).subtracting(result.succeeded) {
                rowsByServer[server] = nil
                cachedOnlyServers.remove(server)
            }
            loadedServers = result.succeeded
        }

        #if !os(tvOS)
            if registry.activeSessions.isEmpty {
                await loadOfflineHome()
            }
        #endif

        rebuild()
        if !hasContent, !result.failed.isEmpty, result.succeeded.isEmpty, !preservingExistingContent {
            errorMessage = String(localized: "home.error.unavailable")
        }
    }

    private func rebuild() {
        let names = Dictionary(
            registry.sessions.map { ($0.identity, $0.name) },
            uniquingKeysWith: { first, _ in first },
        )
        let order = registry.sessions.map(\.identity)
        let homes = order.compactMap { server -> HomeAggregation.ServerHome? in
            guard let rows = rowsByServer[server] else { return nil }
            return HomeAggregation.ServerHome(server: server, serverName: names[server] ?? server.id, rows: rows)
        }
        availableRows = HomeAggregation.merge(
            homes,
            libraryOrder: settingsManager.libraryPreferences(profileID: profileID).libraryOrder,
            showsServerNames: showsServerNames,
            localPlaybackDate: localPlaybackDate(for: homes),
        )
    }

    // MARK: - Offline

    /// Servers shown from their cache until they answer.
    @ObservationIgnored private var cachedOnlyServers: Set<ServerIdentity> = []

    #if !os(tvOS)
        /// The cached home of every server, shown immediately while the servers answer.
        private func showCachedHome() {
            for services in registry.connectedServices where rowsByServer[services.identity] == nil {
                guard let cached = (services.home as? CachedHomeService)?.cachedHome() else { continue }
                rowsByServer[services.identity] = cached.rows
                cachedOnlyServers.insert(services.identity)
            }
            rebuild()
        }

        /// Without any reachable server, each server's offline home (downloads and last cached rows) is aggregated.
        private func loadOfflineHome() async {
            for services in registry.connectedServices {
                let hidden = settingsManager.libraryPreferences(profileID: profileID).hiddenLibraries
                    .filter { $0.server == services.identity }.map(\.libraryID)
                guard let content = try? await services.home.loadHome(
                    hiddenLibraryIDs: Set(hidden),
                    includesPlaylists: settingsManager.interface.displayPlaylists,
                ) else { continue }
                rowsByServer[services.identity] = content.rows
                cachedOnlyServers.insert(services.identity)
            }
        }
    #endif

    private func localPlaybackDate(for homes: [HomeAggregation.ServerHome]) -> (MediaIdentity) -> Date? {
        #if os(tvOS)
            return { _ in nil }
        #else
            guard let store = OfflineCoordinator.shared.store else { return { _ in nil } }
            var dates: [MediaIdentity: Date] = [:]
            for home in homes {
                guard let owner = registry.services(for: home.server)?.owner else { continue }
                let ids = home.rows.filter { $0.kind != .hub }.flatMap(\.items).compactMap(\.playableItem?.id)
                for (id, state) in store.watchStates(itemIDs: ids, owner: owner, localOnly: true) {
                    if let date = state.lastViewedAt {
                        dates[MediaIdentity(server: home.server, itemID: id)] = date
                    }
                }
            }
            return { dates[$0] }
        #endif
    }
}
