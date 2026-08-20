import Combine
import Foundation

@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var isLoading = false
    var selectingServerID: String?
    var isShowingSelectionError = false
    var isShowingCustomAddress = false
    var customAddress = ""
    var customAddressError: String?
    var isSelecting: Bool {
        selectingServerID != nil
    }

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var failedServer: PlexCloudResource?
    @ObservationIgnored private var shouldRetryAfterAlertDismissal = false
    @ObservationIgnored private var shouldShowCustomAddressAfterAlertDismissal = false

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

    func requestCustomAddress() {
        shouldShowCustomAddressAfterAlertDismissal = true
    }

    func handleSelectionErrorDismissal() async {
        guard let failedServer else { return }
        let shouldRetry = shouldRetryAfterAlertDismissal
        let shouldShowCustomAddress = shouldShowCustomAddressAfterAlertDismissal
        shouldRetryAfterAlertDismissal = false
        shouldShowCustomAddressAfterAlertDismissal = false
        await Task.yield()
        guard !Task.isCancelled else { return }
        if shouldRetry {
            await select(server: failedServer)
        } else if shouldShowCustomAddress {
            if customAddress.isEmpty {
                customAddress = context.customServerURL(for: failedServer)?.absoluteString ?? ""
            }
            customAddressError = nil
            isShowingCustomAddress = true
        }
    }

    func connectWithCustomAddress() async {
        guard selectingServerID == nil, let failedServer else { return }

        let url: URL
        do {
            url = try PlexAPIContext.normalizedCustomServerURL(customAddress)
            customAddress = url.absoluteString
        } catch {
            customAddressError = String(localized: "serverSelection.customAddress.error.invalid")
            return
        }

        selectingServerID = failedServer.clientIdentifier
        customAddressError = nil
        defer { selectingServerID = nil }

        do {
            try await sessionManager.selectServer(failedServer, customURL: url)
            self.failedServer = nil
            isShowingCustomAddress = false
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            customAddressError = String(localized: "serverSelection.customAddress.error.connection")
        }
    }

    func dismissCustomAddress() {
        isShowingCustomAddress = false
        customAddressError = nil
        failedServer = nil
    }

    func dismissSelectionError() {
        isShowingSelectionError = false
        failedServer = nil
        shouldRetryAfterAlertDismissal = false
        shouldShowCustomAddressAfterAlertDismissal = false
    }
}
