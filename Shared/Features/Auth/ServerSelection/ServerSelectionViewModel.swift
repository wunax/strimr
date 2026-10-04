import Foundation
import Observation

/// Servers of a Plex account to enable for the profile. Every server is checked by default: many users only reach
/// servers shared with them.
@MainActor
@Observable
final class ServerSelectionViewModel {
    enum ProbeState: Equatable {
        case testing
        case reachable(PlexConnectionKind?)
        case unreachable
    }

    var servers: [PlexCloudResource] = []
    var selectedServerIDs: Set<String> = []
    var isLoading = false
    var loadFailed = false
    var customAddressModel: CustomServerAddressModel?
    private(set) var probes: [String: ProbeState] = [:]

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

    /// Loads the servers, then tests each one so an unreachable or relayed server can get a custom address.
    func load() async {
        isLoading = true
        loadFailed = false
        let loaded: [PlexCloudResource]
        do {
            loaded = try await loadServers()
            isLoading = false
        } catch {
            isLoading = false
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTransportFailure {
                ErrorReporter.capture(error)
            }
            loadFailed = true
            return
        }
        guard !Task.isCancelled else { return }
        servers = loaded
        if !hasLoaded {
            selectedServerIDs = Set(loaded.map(\.clientIdentifier))
            hasLoaded = true
        }
        await probe(loaded)
    }

    func probeState(of server: PlexCloudResource) -> ProbeState? {
        probes[server.clientIdentifier]
    }

    func suggestsCustomAddress(for server: PlexCloudResource) -> Bool {
        switch probes[server.clientIdentifier] {
        case .unreachable, .reachable(.relay):
            true
        default:
            false
        }
    }

    private func probe(_ servers: [PlexCloudResource]) async {
        for server in servers {
            probes[server.clientIdentifier] = .testing
        }
        await withTaskGroup(of: (String, ProbeState?).self) { group in
            for server in servers {
                group.addTask { @MainActor in
                    // Also saves the connection found, so the server connects faster once the profile starts.
                    let context = PlexAPIContext()
                    do {
                        try await context.selectServer(server)
                        return (server.clientIdentifier, .reachable(context.connectionKind))
                    } catch {
                        guard !Task.isCancelled, !error.isCancellation else { return (server.clientIdentifier, nil) }
                        return (server.clientIdentifier, .unreachable)
                    }
                }
            }
            for await (id, state) in group {
                guard let state, probes[id] == .testing else { continue }
                probes[id] = state
            }
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
                self?.probes[server.clientIdentifier] = .reachable(.custom)
            },
            remove: existing == nil ? nil : { context.removeCustomServerURL(for: server) },
            onDone: { [weak self] in self?.customAddressModel = nil },
        )
    }
}
