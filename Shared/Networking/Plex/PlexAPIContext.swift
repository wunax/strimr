import Foundation

@Observable
final class PlexAPIContext {
    private(set) var authTokenCloud: String?
    private(set) var clientIdentifier: String = ""
    private var resource: PlexCloudResource?
    private(set) var baseURLServer: URL?
    private(set) var authTokenServer: String?
    @ObservationIgnored private var bootstrapTask: Task<Void, Never>?

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

    func selectServer(_ resource: PlexCloudResource) async throws {
        self.resource = resource
        baseURLServer = nil
        authTokenServer = resource.accessToken

        try await ensureConnection()
    }

    func removeServer() {
        resource = nil
        baseURLServer = nil
    }

    @discardableResult
    private func ensureConnection() async throws -> URL {
        guard let resource else {
            throw PlexAPIError.missingConnection
        }
        if let baseURLServer {
            return baseURLServer
        }

        if let savedConnection = loadSavedConnection(for: resource),
           let matchingConnection = resource.connections.first(where: { $0.uri == savedConnection }),
           try await isConnectionReachable(matchingConnection, accessToken: resource.accessToken)
        {
            baseURLServer = matchingConnection.uri
            return matchingConnection.uri
        }

        guard let connection = try await resolveConnection(using: resource) else {
            throw PlexAPIError.unreachableServer
        }

        baseURLServer = connection.uri
        storeConnection(connection.uri, for: resource)
        return connection.uri
    }

    private func resolveConnection(using resource: PlexCloudResource) async throws -> PlexCloudResource.Connection? {
        let sortedConnections = resource.connections.sorted { lhs, rhs in
            if lhs.isRelay != rhs.isRelay {
                return rhs.isRelay // non-relay first
            }
            if lhs.isLocal != rhs.isLocal {
                return lhs.isLocal // local first
            }
            return false
        }

        for connection in sortedConnections {
            if try await isConnectionReachable(connection, accessToken: resource.accessToken) {
                return connection
            }
        }

        return nil
    }

    private func isConnectionReachable(
        _ connection: PlexCloudResource.Connection,
        accessToken: String,
    ) async throws -> Bool {
        var request = URLRequest(url: connection.uri)
        request.setValue(accessToken, forHTTPHeaderField: "X-Plex-Token")
        request.timeoutInterval = 6

        do {
            let (_, response) = try await URLSession.shared.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                return false
            }
            return httpResponse.statusCode < 500
        } catch {
            return false
        }
    }

    func reset() {
        resource = nil
        authTokenCloud = nil
        baseURLServer = nil
        authTokenServer = nil
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
