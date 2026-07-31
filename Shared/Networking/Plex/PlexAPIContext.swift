import Foundation

@Observable
final class PlexAPIContext {
    struct ServerAccessSnapshot: Equatable {
        let serverIdentifier: String
        let baseURL: URL
        let authToken: String
        let clientIdentifier: String
        let generation: Int
    }

    private enum ConnectionStatus {
        case reachable
        case unauthorized
        case unavailable
    }

    private(set) var authTokenCloud: String?
    private(set) var clientIdentifier: String = ""
    private var resource: PlexCloudResource?
    private(set) var baseURLServer: URL?
    private(set) var authTokenServer: String?
    private(set) var serverAccessGeneration = 0
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?
    @ObservationIgnored private var recoveryTask: Task<Void, Error>?
    @ObservationIgnored private var recoveryHandler: ((Bool) async throws -> Void)?

    @ObservationIgnored private let keychain = Keychain(service: Bundle.main.bundleIdentifier!)
    @ObservationIgnored private let clientIdKey = "strimr.plex.clientId"
    @ObservationIgnored private let connectionKeyPrefix = "strimr.plex.connection"

    init() {
        bootstrapTask = Task { [weak self] in
            await self?.bootstrap()
        }
    }

    private func bootstrap() async {
        do {
            let cid = try await ensureClientIdentifier()
            clientIdentifier = cid
        } catch {
            let fallback = UUID().uuidString
            clientIdentifier = fallback
        }
    }

    private func ensureClientIdentifier() async throws -> String {
        if let stored = try keychain.string(forKey: clientIdKey) {
            return stored
        }
        let identifier = UUID().uuidString
        try keychain.setString(identifier, forKey: clientIdKey)
        return identifier
    }

    func waitForBootstrap() async {
        await bootstrapTask?.value
    }

    func setAuthToken(_ token: String) {
        authTokenCloud = token
    }

    var serverIdentifier: String? {
        resource?.clientIdentifier
    }

    func selectServer(_ resource: PlexCloudResource) async throws {
        do {
            let connection = try await resolveConnection(using: resource)
            commitServerAccess(resource: resource, connection: connection)
        } catch {
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            throw PlexAPIError.unreachableServer
        }
    }

    func configureServerAccessRecovery(
        _ handler: @escaping (Bool) async throws -> Void,
    ) {
        recoveryHandler = handler
    }

    func serverAccessSnapshot() throws -> ServerAccessSnapshot {
        guard let resource else {
            throw PlexAPIError.missingConnection
        }
        guard let baseURLServer else {
            throw PlexAPIError.missingConnection
        }
        guard let authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }
        return ServerAccessSnapshot(
            serverIdentifier: resource.clientIdentifier,
            baseURL: baseURLServer,
            authToken: authTokenServer,
            clientIdentifier: clientIdentifier,
            generation: serverAccessGeneration,
        )
    }

    func recoverServerAccess(
        afterUnauthorizedSnapshot snapshot: ServerAccessSnapshot,
        force: Bool = false,
    ) async throws {
        if !force, snapshot.generation != serverAccessGeneration {
            return
        }
        if let recoveryTask {
            return try await recoveryTask.value
        }
        guard let recoveryHandler else {
            throw PlexServerAccessRecoveryError.connectionFailed
        }

        let task = Task {
            try await recoveryHandler(force)
        }
        recoveryTask = task
        do {
            try await task.value
            recoveryTask = nil
        } catch {
            recoveryTask = nil
            guard !Task.isCancelled, !error.isCancellation else {
                throw error
            }
            ErrorReporter.capture(error)
            throw error
        }
    }

    func refreshServerAccess(using resource: PlexCloudResource) async throws {
        guard resource.clientIdentifier == serverIdentifier else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        let connection = try await resolveConnection(using: resource)
        commitServerAccess(resource: resource, connection: connection)
    }

    @discardableResult
    func validateCurrentServerAccess() async throws -> Bool {
        let snapshot = try serverAccessSnapshot()
        switch try await connectionStatus(
            snapshot.baseURL,
            accessToken: snapshot.authToken,
        ) {
        case .reachable:
            return false
        case .unauthorized:
            try await recoverServerAccess(afterUnauthorizedSnapshot: snapshot)
            return true
        case .unavailable:
            return false
        }
    }

    func forceRefreshCurrentServerAccess() async throws {
        let snapshot = try serverAccessSnapshot()
        try await recoverServerAccess(
            afterUnauthorizedSnapshot: snapshot,
            force: true,
        )
    }

    func removeServer() {
        resource = nil
        baseURLServer = nil
        authTokenServer = nil
        serverAccessGeneration &+= 1
    }

    private func resolveConnection(
        using resource: PlexCloudResource,
    ) async throws -> PlexCloudResource.Connection {
        guard let accessToken = resource.accessToken else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        var sawUnauthorized = false
        let savedConnection = loadSavedConnection(for: resource)
        if let savedConnection,
           let matchingConnection = resource.connections?.first(where: { $0.uri == savedConnection })
        {
            switch try await connectionStatus(matchingConnection.uri, accessToken: accessToken) {
            case .reachable:
                return matchingConnection
            case .unauthorized:
                sawUnauthorized = true
            case .unavailable:
                break
            }
        }

        guard let connections = resource.connections, !connections.isEmpty else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        let sortedConnections = connections.sorted { lhs, rhs in
            if lhs.isRelay != rhs.isRelay {
                return rhs.isRelay // non-relay first
            }
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal // local first
            }
            return false
        }

        for connection in sortedConnections {
            if connection.uri == savedConnection {
                continue
            }
            switch try await connectionStatus(connection.uri, accessToken: accessToken) {
            case .reachable:
                return connection
            case .unauthorized:
                sawUnauthorized = true
            case .unavailable:
                break
            }
        }

        if sawUnauthorized {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        throw PlexServerAccessRecoveryError.connectionFailed
    }

    private func connectionStatus(
        _ url: URL,
        accessToken: String,
    ) async throws -> ConnectionStatus {
        var request = URLRequest(url: url)
        request.setValue(accessToken, forHTTPHeaderField: "X-Plex-Token")
        request.timeoutInterval = 6

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return .unavailable
            }
            if 200 ..< 300 ~= httpResponse.statusCode {
                return .reachable
            }
            if httpResponse.statusCode == 401 || httpResponse.statusCode == 403 {
                return .unauthorized
            }
            return .unavailable
        } catch {
            if Task.isCancelled || error.isCancellation {
                throw error
            }
            return .unavailable
        }
    }

    private func commitServerAccess(
        resource: PlexCloudResource,
        connection: PlexCloudResource.Connection,
    ) {
        self.resource = resource
        baseURLServer = connection.uri
        authTokenServer = resource.accessToken
        storeConnection(connection.uri, for: resource)
        serverAccessGeneration &+= 1
    }

    func reset() {
        resource = nil
        authTokenCloud = nil
        baseURLServer = nil
        authTokenServer = nil
        recoveryTask?.cancel()
        recoveryTask = nil
        serverAccessGeneration &+= 1
    }

    private func connectionKey(for resource: PlexCloudResource) -> String {
        "\(connectionKeyPrefix).\(resource.clientIdentifier)"
    }

    private func loadSavedConnection(for resource: PlexCloudResource) -> URL? {
        do {
            guard let value = try keychain.string(forKey: connectionKey(for: resource)) else {
                return nil
            }
            return URL(string: value)
        } catch {
            return nil
        }
    }

    private func storeConnection(_ url: URL, for resource: PlexCloudResource) {
        do {
            try keychain.setString(url.absoluteString, forKey: connectionKey(for: resource))
        } catch {
            return
        }
    }
}
