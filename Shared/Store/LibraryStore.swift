import Foundation
import Observation

/// Libraries of every enabled server of the active profile, as one flat list in the profile's order.
@MainActor
@Observable
final class LibraryStore {
    private(set) var librariesByServer: [ServerIdentity: [Library]] = [:]
    private(set) var loadedServers: Set<ServerIdentity> = []
    var isLoading = false
    var loadFailed = false

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var generation = -1

    init(sessionManager: SessionManager, settingsManager: SettingsManager) {
        self.sessionManager = sessionManager
        self.settingsManager = settingsManager
    }

    private var registry: ServerRegistry {
        sessionManager.registry
    }

    var profileID: String {
        sessionManager.activeProfile?.id ?? ""
    }

    /// Every library, hidden ones included, in the profile's order: servers in profile order and each server's own
    /// order until the user reorders them.
    var libraries: [Library] {
        guard generation == registry.generation else { return [] }
        let enabled = registry.enabledSessions.map(\.identity)
        let all = enabled.flatMap { librariesByServer[$0] ?? [] }
        return settingsManager.libraryPreferences(profileID: profileID).ordered(all)
    }

    var visibleLibraries: [Library] {
        let preferences = settingsManager.libraryPreferences(profileID: profileID)
        return libraries.filter { !preferences.isHidden($0.identity) }
    }

    /// Libraries pinned in the tab bar or sidebar, in their pinned order.
    var navigationLibraries: [Library] {
        let byIdentity = Dictionary(libraries.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        return settingsManager.libraryPreferences(profileID: profileID).navigationLibraries
            .compactMap { byIdentity[$0] }
    }

    var showsServerNames: Bool {
        Set(libraries.map(\.server)).count > 1
    }

    func library(_ identity: LibraryIdentity) -> Library? {
        librariesByServer[identity.server]?.first { $0.id == identity.libraryID }
    }

    func serverName(for library: Library) -> String? {
        registry.serverName(for: library.server)
    }

    func loadLibraries() async throws {
        resetIfProfileChanged()
        guard !isLoading else { return }
        let pending = registry.readyServers.subtracting(loadedServers)
        guard !pending.isEmpty || loadedServers.isEmpty else { return }
        try await load(servers: loadedServers.isEmpty ? nil : pending)
    }

    func reloadLibraries() async throws {
        resetIfProfileChanged()
        try await load(servers: nil)
    }

    /// Adds the libraries of servers that became ready and drops those of disabled servers.
    func syncServers() async {
        resetIfProfileChanged()
        let enabled = Set(registry.enabledSessions.map(\.identity))
        for server in Set(librariesByServer.keys).subtracting(enabled) {
            librariesByServer[server] = nil
            loadedServers.remove(server)
        }
        let arrived = registry.readyServers.subtracting(loadedServers)
        guard !arrived.isEmpty, !isLoading else { return }
        try? await load(servers: arrived)
    }

    private func load(servers: Set<ServerIdentity>?) async throws {
        isLoading = true
        loadFailed = false
        defer { isLoading = false }
        let sessions = registry.sessions.filter { servers?.contains($0.identity) ?? true }
        let result = await sessionManager.aggregation.fanOut(servers: sessions) { services in
            try await services.library.libraries()
        }
        if !result.cancelled.isEmpty, result.succeeded.isEmpty {
            throw CancellationError()
        }
        for (server, libraries) in result.value {
            librariesByServer[server] = libraries
            // Settings of libraries deleted on the server are only dropped after this successful load.
            settingsManager.pruneLibraries(of: server, keeping: Set(libraries.map(\.id)))
        }
        loadedServers.formUnion(result.succeeded)
        #if !os(tvOS)
            // Unreachable servers still list their cached libraries.
            for server in result.skipped.union(result.failed) where librariesByServer[server] == nil {
                guard let services = registry.services(for: server),
                      let cached = try? await services.library.libraries()
                else { continue }
                librariesByServer[server] = cached
            }
        #endif
        loadFailed = librariesByServer.isEmpty && !result.failed.isEmpty
    }

    private func resetIfProfileChanged() {
        guard generation != registry.generation else { return }
        generation = registry.generation
        librariesByServer = [:]
        loadedServers = []
        loadFailed = false
    }
}
