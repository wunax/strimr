import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let plexApi: PlexAPIManager

    init(sessionManager: SessionManager, plexApiManager: PlexAPIManager) {
        self.sessionManager = sessionManager
        plexApi = plexApiManager
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            servers = try await plexApi.cloud.getResources().filter { !$0.connections.isEmpty }
        } catch {
            servers = []
        }
    }

    func select(server: PlexCloudResource) {
        sessionManager.selectServer(server)
    }
}
