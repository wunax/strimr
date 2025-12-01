import Foundation
import Observation

@MainActor
@Observable
final class HomeViewModel {
    var continueWatching: Hub?
    var recentlyAdded: [Hub] = []
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let plexApiManager: PlexAPIManager
    @ObservationIgnored private var loadTask: Task<Void, Never>?

    init(plexApiManager: PlexAPIManager) {
        self.plexApiManager = plexApiManager
    }

    var hasContent: Bool {
        (continueWatching?.hasItems ?? false) || recentlyAdded.contains(where: \.hasItems)
    }

    func load() async {
        guard continueWatching == nil && recentlyAdded.isEmpty else { return }
        await reload()
    }

    func reload() async {
        loadTask?.cancel()

        guard let api = plexApiManager.server else {
            resetState(error: "Select a server to load content.")
            return
        }

        let task = Task { [weak self] in
            await self?.fetchHubs(using: api)
            return
        }
        loadTask = task
        await task.value
    }

    private func fetchHubs(using api: PlexMediaServerAPI) async {        
        isLoading = true
        errorMessage = nil
        defer {
            isLoading = false
        }

        do {
            async let continueResponse = api.getContinueWatchingHub()
            async let promotedResponse = api.getPromotedHub()

            let continueHub = try await continueResponse.mediaContainer.hub.first
            let promotedHubs = try await promotedResponse.mediaContainer.hub

            guard !Task.isCancelled else { return }

            continueWatching = continueHub.map(mapHub)
            recentlyAdded = promotedHubs
                .filter { $0.hubIdentifier.lowercased().contains("recentlyadded") }
                .map(mapHub)
        } catch {
            guard !Task.isCancelled else { return }
            resetState(error: error.localizedDescription)
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
}
