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
    var customAddressModel: CustomServerAddressModel?

    @ObservationIgnored private let loadServers: () async throws -> [PlexCloudResource]
    @ObservationIgnored private let onContinue: (Set<String>) -> Void
    @ObservationIgnored private var hasLoaded = false

    /// - Parameter onContinue: receives the ids of the unchecked servers.
    init(
        loadServers: @escaping () async throws -> [PlexCloudResource],
        onContinue: @escaping (Set<String>) -> Void,
    ) {
        self.loadServers = loadServers
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
        let context = PlexAPIContext()
        let existing = context.customServerURL(for: server)
        customAddressModel = CustomServerAddressModel(
            address: existing,
            save: { [weak self] url in
                try await context.selectServer(server, customURL: url)
                self?.selectedServerIDs.insert(server.clientIdentifier)
            },
            remove: existing == nil ? nil : { context.removeCustomServerURL(for: server) },
            onDone: { [weak self] in self?.customAddressModel = nil },
        )
    }
}
