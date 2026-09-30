import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var availableRows: [HomeRow] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let service: any MediaHomeService
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let libraryStore: LibraryStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(services: MediaServices, settingsManager: SettingsManager, libraryStore: LibraryStore) {
        service = services.home
        self.settingsManager = settingsManager
        self.libraryStore = libraryStore
        preferencesScopeID = services.homeRowPreferencesScopeID
    }

    @ObservationIgnored private let preferencesScopeID: String

    var orderedRowsForEditing: [HomeRow] {
        let preferences = settingsManager.homeRowPreferences(for: preferencesScopeID)
        return pinningOfflineDownloads(preferences.orderedRows(from: availableRows), preferences: preferences)
    }

    var rows: [HomeRow] {
        let preferences = settingsManager.homeRowPreferences(for: preferencesScopeID)
        return pinningOfflineDownloads(preferences.visibleRows(from: availableRows), preferences: preferences)
    }

    /// The offline "Downloads" row goes first unless the user placed it somewhere else.
    private func pinningOfflineDownloads(_ rows: [HomeRow], preferences: HomeRowPreferences) -> [HomeRow] {
        #if os(tvOS)
            rows
        #else
            guard let index = rows.firstIndex(where: CachedHomeService.isOfflineDownloadsRow),
                  !preferences.orderedRowIDs.contains(rows[index].id)
            else { return rows }
            var reordered = rows
            reordered.insert(reordered.remove(at: index), at: 0)
            return reordered
        #endif
    }

    func isRowVisible(_ rowID: String) -> Bool {
        !settingsManager.homeRowPreferences(for: preferencesScopeID).hiddenRowIDs.contains(rowID)
    }

    func setRowVisible(_ rowID: String, visible: Bool) {
        settingsManager.setHomeRowVisibility(rowID, visible: visible, scopeID: preferencesScopeID)
    }

    func moveRow(at index: Int, by offset: Int) {
        var rowIDs = orderedRowsForEditing.map(\.id)
        let destination = index + offset
        guard rowIDs.indices.contains(index), rowIDs.indices.contains(destination) else { return }
        let rowID = rowIDs.remove(at: index)
        rowIDs.insert(rowID, at: destination)
        settingsManager.setHomeRowOrder(rowIDs, scopeID: preferencesScopeID)
    }

    func resetRowPreferences() {
        settingsManager.resetHomeRows(scopeID: preferencesScopeID)
    }

    var hasContent: Bool {
        rows.contains { $0.hub.hasItems }
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await reload(preservingExistingContent: false)
    }

    /// Reloads without clearing what is on screen, e.g. after the server became reachable again.
    func refreshSilently() async {
        await reload(preservingExistingContent: true)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }
        await reload(preservingExistingContent: true)
    }

    private func reload(preservingExistingContent: Bool) async {
        loadTask?.cancel()

        let task = Task { [weak self] in
            guard let self else { return }
            await fetchHubs(preservingExistingContent: preservingExistingContent)
        }
        loadTask = task
        await task.value
    }

    private func fetchHubs(preservingExistingContent: Bool) async {
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        #if !os(tvOS)
            if availableRows.isEmpty, let cached = (service as? CachedHomeService)?.cachedHome() {
                availableRows = cached.rows
            }
        #endif

        do {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
            let content = try await service.loadHome(
                hiddenLibraryIDs: Set(settingsManager.interface.hiddenLibraryIds),
                includesPlaylists: settingsManager.interface.displayPlaylists,
            )

            guard !Task.isCancelled else { return }

            availableRows = content.rows
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func resetState(error: String? = nil) {
        availableRows = []
        errorMessage = error
        isLoading = false
    }

    private func handleLoadError(_ message: String, preservingExistingContent: Bool) {
        if preservingExistingContent, hasContent {
            errorMessage = nil
            isLoading = false
        } else {
            resetState(error: message)
        }
    }
}
