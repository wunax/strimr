import Foundation
import Observation

/// Servers of a Plex account to enable for the profile. Every server is checked by default: many users only reach
/// servers shared with them.
@MainActor
@Observable
final class ServerSelectionViewModel {
    var servers: [PlexCloudResource] = []
    var selectedServerIDs: Set<String> = []
    var isLoading = false
    var loadFailed = false
    var selectingServerID: String?
    var isShowingCustomAddress = false
    var customAddress = ""
    var customAddressError: String?

    var isSelecting: Bool {
        selectingServerID != nil
    }

    @ObservationIgnored private let loadServers: () async throws -> [PlexCloudResource]
    @ObservationIgnored private let userToken: () -> String?
    @ObservationIgnored private let onContinue: (Set<String>) -> Void
    @ObservationIgnored private var customAddressServer: PlexCloudResource?
    @ObservationIgnored private var hasLoaded = false

    /// - Parameter onContinue: receives the ids of the unchecked servers.
    init(
        loadServers: @escaping () async throws -> [PlexCloudResource],
        userToken: @escaping () -> String?,
        onContinue: @escaping (Set<String>) -> Void,
    ) {
        self.loadServers = loadServers
        self.userToken = userToken
        self.onContinue = onContinue
    }

    func load() async {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        do {
            let loaded = try await loadServers()
            guard !Task.isCancelled else { return }
            servers = loaded
            if !hasLoaded {
                selectedServerIDs = Set(loaded.map(\.clientIdentifier))
                hasLoaded = true
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTransportFailure {
                ErrorReporter.capture(error)
            }
            loadFailed = true
        }
    }

    func isSelected(_ server: PlexCloudResource) -> Bool {
        selectedServerIDs.contains(server.clientIdentifier)
    }

    func toggle(_ server: PlexCloudResource) {
        if selectedServerIDs.contains(server.clientIdentifier) {
            selectedServerIDs.remove(server.clientIdentifier)
        } else {
            selectedServerIDs.insert(server.clientIdentifier)
        }
    }

    func continueWithSelection() {
        let disabled = Set(servers.map(\.clientIdentifier)).subtracting(selectedServerIDs)
        onContinue(disabled)
    }

    // MARK: - Custom address

    func showCustomAddress(for server: PlexCloudResource) {
        customAddressServer = server
        customAddress = PlexAPIContext().customServerURL(for: server)?.absoluteString ?? ""
        customAddressError = nil
        isShowingCustomAddress = true
    }

    /// Checks the address with the server and stores it; the server then connects through it.
    func connectWithCustomAddress() async {
        guard selectingServerID == nil, let server = customAddressServer else { return }

        let url: URL
        do {
            url = try PlexAPIContext.normalizedCustomServerURL(customAddress)
            customAddress = url.absoluteString
        } catch {
            customAddressError = String(localized: "serverSelection.customAddress.error.invalid")
            return
        }

        selectingServerID = server.clientIdentifier
        customAddressError = nil
        defer { selectingServerID = nil }

        do {
            let context = PlexAPIContext()
            await context.waitForBootstrap()
            if let token = userToken() {
                context.setAuthToken(token)
            }
            try await context.selectServer(server, customURL: url)
            selectedServerIDs.insert(server.clientIdentifier)
            isShowingCustomAddress = false
            customAddressServer = nil
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            customAddressError = String(localized: "serverSelection.customAddress.error.connection")
        }
    }

    func dismissCustomAddress() {
        isShowingCustomAddress = false
        customAddressError = nil
        customAddressServer = nil
    }
}
