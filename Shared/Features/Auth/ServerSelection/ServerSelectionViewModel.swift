import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        self.context = context
    }

    func load() async {
        isLoading = true
        defer { isLoading = false }

        do {
            let repository = ResourceRepository(context: context)
            servers = try await repository.getResources().filter { resource in
                let hasConnections = !(resource.connections?.isEmpty ?? true)
                let hasAccessToken = resource.accessToken != nil
                return hasConnections && hasAccessToken
            }
        } catch {
            ErrorReporter.capture(error)
            servers = []
        }
    }

    func select(server: PlexCloudResource) async {
        await sessionManager.selectServer(server)
    }
}
