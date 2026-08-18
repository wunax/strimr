import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var continueWatching: Hub?
    var recentlyAdded: [Hub] = []
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
    }

    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || recentlyAdded.contains(where: \.hasItems)
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await reload(preservingExistingContent: false)
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

        do {
            if libraryStore.libraries.isEmpty {
                try? await libraryStore.loadLibraries()
            }
            let content = try await service.loadHome(
                hiddenLibraryIDs: Set(settingsManager.interface.hiddenLibraryIds),
                includesPlaylists: settingsManager.interface.displayPlaylists,
            )

            guard !Task.isCancelled else { return }

            continueWatching = content.continueWatching
            recentlyAdded = content.recentlyAdded
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func resetState(error: String? = nil) {
        continueWatching = nil
        recentlyAdded = []
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
