import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false
    var selectingServerID: String?
    var isShowingSelectionError = false
    var isSelecting: Bool {
        selectingServerID != nil
    }

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var failedServer: PlexCloudResource?
    @ObservationIgnored private var shouldRetryAfterAlertDismissal = false

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
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            servers = []
        }
    }

    func select(server: PlexCloudResource) async {
        guard selectingServerID == nil else { return }
        selectingServerID = server.clientIdentifier
        defer { selectingServerID = nil }

        do {
            try await sessionManager.selectServer(server)
            failedServer = nil
            isShowingSelectionError = false
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            failedServer = server
            isShowingSelectionError = true
        }
    }

    func requestSelectionRetry() {
        shouldRetryAfterAlertDismissal = true
    }

    func retrySelectionAfterAlertDismissal() async {
        guard shouldRetryAfterAlertDismissal, let failedServer else { return }
        shouldRetryAfterAlertDismissal = false
        await Task.yield()
        guard !Task.isCancelled else { return }
        await select(server: failedServer)
    }

    func dismissSelectionError() {
        isShowingSelectionError = false
        failedServer = nil
        shouldRetryAfterAlertDismissal = false
    }
}
