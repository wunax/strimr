import Foundation

@Observable
final class PlexAPIContext {
    private(set) var authToken: String?
    private(set) var clientIdentifier: String = ""
    private var resource: PlexCloudResource?
    private(set) var baseURLServer: URL?

    @ObservationIgnored private let keychain = Keychain(service: "dev.strimr.app")
    @ObservationIgnored private let clientIdKey = "strimr.plex.clientId"

    init() {
        Task {
            await bootstrap()
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
    
    func setAuthToken(_ token: String) {
        authToken = token
    }

    func selectServer(_ resource: PlexCloudResource) async throws {
        self.resource = resource
        baseURLServer = nil
        
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

        guard let connection = try await resolveConnection(using: resource) else {
            throw PlexAPIError.unreachableServer
        }

        baseURLServer = connection.uri
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

    private func isConnectionReachable(_ connection: PlexCloudResource.Connection, accessToken: String) async throws -> Bool {
        var request = URLRequest(url: connection.uri)
        request.setValue(accessToken, forHTTPHeaderField: "X-Plex-Token")
        request.timeoutInterval = 3

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
        authToken = nil
        baseURLServer = nil
    }
}
