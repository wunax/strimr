import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var continueWatching: Hub?
    var recentlyAdded: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let libraryStore: LibraryStore
    @ObservationIgnored private var loadTask: Task<Void, Never>?
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(context: PlexAPIContext, settingsManager: SettingsManager, libraryStore: LibraryStore) {
        self.context = context
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
        guard let hubRepository = try? HubRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.loadContent"),
                preservingExistingContent: preservingExistingContent,
            )
            return
        }

        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            let hubParams: HubRepository.HubParams? = await {
                let hiddenLibraryIds = settingsManager.interface.hiddenLibraryIds
                guard !hiddenLibraryIds.isEmpty else { return nil }

                if libraryStore.libraries.isEmpty {
                    try? await libraryStore.loadLibraries()
                }

                let visibleSectionIds = libraryStore.libraries
                    .filter { !hiddenLibraryIds.contains($0.id) }
                    .compactMap(\.sectionId)

                return HubRepository.HubParams(sectionIds: visibleSectionIds)
            }()

            async let continueResponse = hubRepository.getContinueWatchingHub(params: hubParams)
            async let promotedResponse = hubRepository.getPromotedHub(
                params: hubParams,
                includeLibraryPlaylists: settingsManager.interface.displayPlaylists,
            )

            let continueHub = try await continueResponse.mediaContainer.hub?.first
            let promotedHubs = try await promotedResponse.mediaContainer.hub ?? []

            guard !Task.isCancelled else { return }

            continueWatching = continueHub.map(mapHub)
            recentlyAdded = promotedHubs
                .filter { $0.hubIdentifier.lowercased().contains("recentlyadded") && $0.size > 0 }
                .map(mapHub)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            handleLoadError(error.localizedDescription, preservingExistingContent: preservingExistingContent)
        }
    }

    private func mapHub(_ hub: PlexHub) -> Hub {
        Hub(plexHub: hub)
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
