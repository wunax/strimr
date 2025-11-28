import Foundation
import Combine

@MainActor
final class ServerSelectionViewModel: ObservableObject {
    @Published var servers: [PlexCloudResource] = []
    @Published var isLoading = false

    private let sessionCoordinator: SessionCoordinator

    init(sessionCoordinator: SessionCoordinator) {
        self.sessionCoordinator = sessionCoordinator
    }

    func load() async {
        guard let cloudAPI = sessionCoordinator.cloudAPI else {
            servers = []
            return
        }

        isLoading = true
        defer { isLoading = false }

        do {
            servers = try await cloudAPI.getResources().filter { !$0.connections.isEmpty }
        } catch {
            servers = []
        }
    }

    func select(server: PlexCloudResource) {
        sessionCoordinator.selectServer(server)
    }
}
