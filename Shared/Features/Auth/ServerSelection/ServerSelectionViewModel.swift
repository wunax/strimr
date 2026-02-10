import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false
    var selectingServerID: String?
    var isSelecting: Bool { selectingServerID != nil }

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
            servers = try await repository.getAvailableResources()
        } catch {
            ErrorReporter.capture(error)
            servers = []
        }
    }

    func select(server: PlexCloudResource) async {
        guard selectingServerID == nil else { return }
        selectingServerID = server.clientIdentifier
        defer { selectingServerID = nil }

        await sessionManager.selectServer(server)
    }
}
