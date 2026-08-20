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

    private enum ConnectionStatus: Sendable {
        case reachable
        case unauthorized
        case unavailable
    }

    private enum ConnectionResolutionEvent: Sendable {
        case probeFinished(index: Int, status: ConnectionStatus)
        case localPreferenceExpired
        case relayEligible
        case deadlineReached
    }

    private static let localConnectionGrace: Duration = .milliseconds(500)
    private static let relayProbeDelay: Duration = .milliseconds(750)
    private static let relayDecisionDelay: Duration = .seconds(2)
    private static let connectionResolutionDeadline: Duration = .seconds(6)

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
    @ObservationIgnored private let customConnectionKeyPrefix = "strimr.plex.customConnection"

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

    func selectServer(_ resource: PlexCloudResource, customURL: URL? = nil) async throws {
        do {
            if let customURL {
                try await validateCustomConnection(customURL, using: resource)
                storeCustomConnection(customURL, for: resource)
                commitServerAccess(resource: resource, url: customURL)
            } else {
                let url = try await resolveServerURL(using: resource)
                commitServerAccess(resource: resource, url: url)
            }
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
        let url = try await resolveServerURL(using: resource)
        commitServerAccess(resource: resource, url: url)
    }

    @discardableResult
    func validateCurrentServerAccess() async throws -> Bool {
        let snapshot = try serverAccessSnapshot()
        switch try await Self.connectionStatus(
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

    static func normalizedCustomServerURL(_ value: String) throws -> URL {
        let normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty,
              var components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = components.host,
              !host.isEmpty,
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil
        else {
            throw PlexAPIError.invalidURL
        }

        components.scheme = scheme
        while components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }
        return url
    }

    func customServerURL(for resource: PlexCloudResource) -> URL? {
        loadCustomConnection(for: resource)
    }

    private func resolveServerURL(using resource: PlexCloudResource) async throws -> URL {
        if let customURL = loadCustomConnection(for: resource),
           try await isReachable(customURL, using: resource)
        {
            return customURL
        }
        return try await resolveConnection(using: resource).uri
    }

    private func validateCustomConnection(
        _ url: URL,
        using resource: PlexCloudResource,
    ) async throws {
        guard let accessToken = resource.accessToken else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        switch try await Self.connectionStatus(url, accessToken: accessToken) {
        case .reachable:
            return
        case .unauthorized:
            throw PlexServerAccessRecoveryError.serverUnavailable
        case .unavailable:
            throw PlexServerAccessRecoveryError.connectionFailed
        }
    }

    private func isReachable(
        _ url: URL,
        using resource: PlexCloudResource,
    ) async throws -> Bool {
        guard let accessToken = resource.accessToken else { return false }
        return try await Self.connectionStatus(url, accessToken: accessToken) == .reachable
    }

    private func resolveConnection(
        using resource: PlexCloudResource,
    ) async throws -> PlexCloudResource.Connection {
        guard let accessToken = resource.accessToken else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }
        guard let resourceConnections = resource.connections, !resourceConnections.isEmpty else {
            throw PlexServerAccessRecoveryError.serverUnavailable
        }

        var seenURIs = Set<URL>()
        var connections = resourceConnections.filter { connection in
            seenURIs.insert(connection.uri).inserted
        }
        if let savedConnection = loadSavedConnection(for: resource),
           let savedIndex = connections.firstIndex(where: { $0.uri == savedConnection })
        {
            let savedCandidate = connections.remove(at: savedIndex)
            connections.insert(savedCandidate, at: 0)
        }

        return try await withThrowingTaskGroup(of: ConnectionResolutionEvent.self) { group in
            defer { group.cancelAll() }

            for (index, connection) in connections.enumerated() {
                let uri = connection.uri
                let isRelay = connection.isRelay
                group.addTask {
                    if isRelay {
                        try await Task.sleep(for: Self.relayProbeDelay)
                    }
                    let status = try await Self.connectionStatus(uri, accessToken: accessToken)
                    return .probeFinished(index: index, status: status)
                }
            }

            group.addTask {
                try await Task.sleep(for: Self.relayDecisionDelay)
                return .relayEligible
            }
            group.addTask {
                try await Task.sleep(for: Self.connectionResolutionDeadline)
                return .deadlineReached
            }

            var remainingProbeCount = connections.count
            var remainingLocalProbeCount = connections.filter {
                $0.isLocal && !$0.isRelay
            }.count
            var sawUnauthorized = false
            var remoteCandidate: PlexCloudResource.Connection?
            var relayCandidate: PlexCloudResource.Connection?
            var isLocalPreferenceTimerScheduled = false
            var isRelayEligible = false

            while let event = try await group.next() {
                switch event {
                case let .probeFinished(index, status):
                    let connection = connections[index]
                    remainingProbeCount -= 1
                    if connection.isLocal, !connection.isRelay {
                        remainingLocalProbeCount -= 1
                    }

                    switch status {
                    case .reachable:
                        if connection.isLocal, !connection.isRelay {
                            return connection
                        }
                        if !connection.isRelay {
                            if remoteCandidate == nil {
                                remoteCandidate = connection
                            }
                            if !isLocalPreferenceTimerScheduled {
                                isLocalPreferenceTimerScheduled = true
                                group.addTask {
                                    try await Task.sleep(for: Self.localConnectionGrace)
                                    return .localPreferenceExpired
                                }
                            }
                        } else {
                            if relayCandidate == nil {
                                relayCandidate = connection
                            }
                        }
                    case .unauthorized:
                        sawUnauthorized = true
                    case .unavailable:
                        break
                    }

                    if let remoteCandidate, remainingLocalProbeCount == 0 {
                        return remoteCandidate
                    }
                    if isRelayEligible, remoteCandidate == nil, let relayCandidate {
                        return relayCandidate
                    }
                    if remainingProbeCount == 0,
                       remoteCandidate == nil,
                       relayCandidate == nil
                    {
                        if sawUnauthorized {
                            throw PlexServerAccessRecoveryError.serverUnavailable
                        }
                        throw PlexServerAccessRecoveryError.connectionFailed
                    }

                case .localPreferenceExpired:
                    if let remoteCandidate {
                        return remoteCandidate
                    }

                case .relayEligible:
                    isRelayEligible = true
                    if remoteCandidate == nil, let relayCandidate {
                        return relayCandidate
                    }

                case .deadlineReached:
                    if let remoteCandidate {
                        return remoteCandidate
                    }
                    if let relayCandidate {
                        return relayCandidate
                    }
                    if sawUnauthorized {
                        throw PlexServerAccessRecoveryError.serverUnavailable
                    }
                    throw PlexServerAccessRecoveryError.connectionFailed
                }
            }

            if sawUnauthorized {
                throw PlexServerAccessRecoveryError.serverUnavailable
            }
            throw PlexServerAccessRecoveryError.connectionFailed
        }
    }

    private static func connectionStatus(
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

    private func commitServerAccess(resource: PlexCloudResource, url: URL) {
        self.resource = resource
        baseURLServer = url
        authTokenServer = resource.accessToken
        storeConnection(url, for: resource)
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

    private func customConnectionKey(for resource: PlexCloudResource) -> String {
        "\(customConnectionKeyPrefix).\(resource.clientIdentifier)"
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

    private func loadCustomConnection(for resource: PlexCloudResource) -> URL? {
        do {
            guard let value = try keychain.string(forKey: customConnectionKey(for: resource)) else {
                return nil
            }
            return URL(string: value)
        } catch {
            return nil
        }
    }

    private func storeCustomConnection(_ url: URL, for resource: PlexCloudResource) {
        do {
            try keychain.setString(url.absoluteString, forKey: customConnectionKey(for: resource))
        } catch {
            return
        }
    }
}
