import Foundation
import Observation

enum JellyfinAPIError: LocalizedError, Equatable {
    case invalidServerURL
    case unsupportedServer
    case serverUnreachable
    case invalidCredentials
    case authenticationRequired
    case permissionDenied
    case itemUnavailable
    case noPlayableSource
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidServerURL:
            String(localized: "jellyfin.errors.invalidURL")
        case .unsupportedServer:
            String(localized: "jellyfin.errors.unsupportedServer")
        case .serverUnreachable:
            String(localized: "jellyfin.errors.serverUnreachable")
        case .invalidCredentials:
            String(localized: "jellyfin.errors.invalidCredentials")
        case .authenticationRequired:
            String(localized: "jellyfin.errors.authenticationRequired")
        case .permissionDenied:
            String(localized: "jellyfin.errors.permissionDenied")
        case .itemUnavailable:
            String(localized: "jellyfin.errors.itemUnavailable")
        case .noPlayableSource:
            String(localized: "jellyfin.errors.noDirectPlaySource")
        case .invalidResponse, .httpStatus:
            String(localized: "jellyfin.errors.invalidResponse")
        }
    }
}

@MainActor
@Observable
final class JellyfinAPIContext {
    private(set) var connection: JellyfinConnection?
    private(set) var currentUser: JellyfinUser?
    private(set) var capabilities = ProviderCapabilities.jellyfin

    @ObservationIgnored private var accessToken: String?
    @ObservationIgnored private let session: URLSession
    @ObservationIgnored private let redirectDelegate: JellyfinRedirectDelegate?
    @ObservationIgnored private let deviceID: String
    @ObservationIgnored private let clientVersion: String
    @ObservationIgnored private var authenticationRequiredHandler: (() -> Void)?

    init(session: URLSession? = nil) {
        if let session {
            self.session = session
            redirectDelegate = nil
        } else {
            let redirectDelegate = JellyfinRedirectDelegate()
            self.redirectDelegate = redirectDelegate
            self.session = URLSession(
                configuration: .default,
                delegate: redirectDelegate,
                delegateQueue: nil,
            )
        }
        clientVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"

        let keychain = Keychain(service: Bundle.main.bundleIdentifier ?? "com.strimr.app")
        let key = "strimr.deviceIdentifier"
        if let stored = try? keychain.string(forKey: key), !stored.isEmpty {
            deviceID = stored
        } else {
            let generated = UUID().uuidString.lowercased()
            deviceID = generated
            do {
                try keychain.setString(generated, forKey: key)
            } catch {
                ErrorReporter.capture(error)
            }
        }
    }

    var isAuthenticated: Bool {
        connection != nil && accessToken != nil
    }

    var serverIdentity: ServerIdentity? {
        connection?.serverIdentity
    }

    func validateServerURL(_ value: String) async throws -> (JellyfinPublicSystemInfo, URL) {
        let baseURL = try Self.normalizedServerURL(value)
        let (data, response) = try await perform(
            baseURL: baseURL,
            path: ["System", "Info", "Public"],
            method: "GET",
            query: [],
            body: nil,
            token: nil,
        )

        guard response.statusCode == 200 else {
            throw JellyfinAPIError.unsupportedServer
        }

        let info: JellyfinPublicSystemInfo
        do {
            info = try JSONDecoder().decode(JellyfinPublicSystemInfo.self, from: data)
        } catch {
            throw JellyfinAPIError.unsupportedServer
        }

        guard !info.id.isEmpty, !info.serverName.isEmpty else {
            throw JellyfinAPIError.unsupportedServer
        }

        let effectiveURL = response.url.map {
            Self.baseURL(fromResponseURL: $0, removingPathComponents: 3)
        } ?? baseURL
        return (info, effectiveURL)
    }

    func authenticate(
        server: JellyfinPublicSystemInfo,
        baseURL: URL,
        username: String,
        password: String,
    ) async throws -> (JellyfinAuthenticatedSession, JellyfinConnection) {
        struct Body: Encodable {
            let Username: String
            let Pw: String
        }

        let body = try JSONEncoder().encode(Body(Username: username, Pw: password))
        let (data, response) = try await perform(
            baseURL: baseURL,
            path: ["Users", "AuthenticateByName"],
            method: "POST",
            query: [],
            body: body,
            token: nil,
        )

        guard response.statusCode != 400, response.statusCode != 401 else {
            throw JellyfinAPIError.invalidCredentials
        }
        try validateStatus(response.statusCode)

        let authenticated: JellyfinAuthenticatedSession
        do {
            authenticated = try JSONDecoder().decode(JellyfinAuthenticatedSession.self, from: data)
        } catch {
            throw JellyfinAPIError.invalidResponse
        }

        guard !authenticated.accessToken.isEmpty,
              !authenticated.user.id.isEmpty,
              authenticated.serverID == server.id
        else {
            throw JellyfinAPIError.invalidResponse
        }

        let connection = JellyfinConnection(
            baseURL: baseURL,
            serverID: server.id,
            serverName: server.serverName,
            serverVersion: server.version,
            userID: authenticated.user.id,
            username: authenticated.user.name,
        )
        configure(connection: connection, token: authenticated.accessToken)
        currentUser = authenticated.user
        return (authenticated, connection)
    }

    func configure(connection: JellyfinConnection, token: String) {
        self.connection = connection
        accessToken = token
        currentUser = nil
    }

    func configureAuthenticationRequiredHandler(_ handler: @escaping () -> Void) {
        authenticationRequiredHandler = handler
    }

    func reset() {
        connection = nil
        currentUser = nil
        accessToken = nil
        capabilities = .jellyfin
    }

    func validateAuthenticatedSession() async throws -> JellyfinUser {
        try await refreshCurrentUser()
    }

    @discardableResult
    func refreshCurrentUser() async throws -> JellyfinUser {
        guard let connection else { throw JellyfinAPIError.authenticationRequired }
        let user: JellyfinUser = try await get(path: ["Users", connection.userID], query: [])
        guard user.id == connection.userID else { throw JellyfinAPIError.invalidResponse }
        currentUser = user
        return user
    }

    var authorization: MediaAuthorization {
        guard let policy = currentUser?.policy else { return .denied }
        let isAdministrator = policy.isAdministrator == true
        return MediaAuthorization(
            isAdministrator: isAdministrator,
            canManageSubtitles: isAdministrator || policy.enableSubtitleManagement == true,
            canManageServer: isAdministrator
        )
    }

    func get<Response: Decodable & Sendable>(
        path: [String],
        query: [URLQueryItem] = [],
    ) async throws -> Response {
        try await request(path: path, method: "GET", query: query, body: nil)
    }

    func post<Response: Decodable & Sendable>(
        path: [String],
        query: [URLQueryItem] = [],
        body: some Encodable,
    ) async throws -> Response {
        let encoded = try JSONEncoder().encode(body)
        return try await request(path: path, method: "POST", query: query, body: encoded)
    }

    func send(
        path: [String],
        method: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
    ) async throws {
        let (_, response) = try await authenticatedRequest(
            path: path,
            method: method,
            query: query,
            body: body,
        )
        try validateStatus(response.statusCode)
    }

    func mediaRequest(url: URL) throws -> URLRequest {
        guard accessToken != nil else { throw JellyfinAPIError.authenticationRequired }
        var request = URLRequest(url: url)
        authorizationHeaders().forEach { request.setValue($0.value, forHTTPHeaderField: $0.key) }
        return request
    }

    func data(for request: URLRequest) async throws -> Data {
        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinAPIError.invalidResponse
            }
            try validateStatus(httpResponse.statusCode)
            return data
        } catch let error as JellyfinAPIError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw error
            }
            throw JellyfinAPIError.serverUnreachable
        }
    }

    func url(path: [String], query: [URLQueryItem] = []) throws -> URL {
        guard let baseURL = connection?.baseURL else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try Self.makeURL(baseURL: baseURL, path: path, query: query)
    }

    func playbackHeaders() throws -> [String: String] {
        guard accessToken != nil else { throw JellyfinAPIError.authenticationRequired }
        return authorizationHeaders()
    }

    private func request<Response: Decodable & Sendable>(
        path: [String],
        method: String,
        query: [URLQueryItem],
        body: Data?,
    ) async throws -> Response {
        let (data, response) = try await authenticatedRequest(
            path: path,
            method: method,
            query: query,
            body: body,
        )
        try validateStatus(response.statusCode)
        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            ErrorReporter.capture(JellyfinAPIError.invalidResponse)
            throw JellyfinAPIError.invalidResponse
        }
    }

    private func authenticatedRequest(
        path: [String],
        method: String,
        query: [URLQueryItem],
        body: Data?,
    ) async throws -> (Data, HTTPURLResponse) {
        guard let connection, let accessToken else {
            throw JellyfinAPIError.authenticationRequired
        }
        return try await perform(
            baseURL: connection.baseURL,
            path: path,
            method: method,
            query: query,
            body: body,
            token: accessToken,
        )
    }

    private func perform(
        baseURL: URL,
        path: [String],
        method: String,
        query: [URLQueryItem],
        body: Data?,
        token: String?,
    ) async throws -> (Data, HTTPURLResponse) {
        let url = try Self.makeURL(baseURL: baseURL, path: path, query: query)
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.httpBody = body
        request.timeoutInterval = 15
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        for authorizationHeader in authorizationHeaders(token: token) {
            request.setValue(authorizationHeader.value, forHTTPHeaderField: authorizationHeader.key)
        }

        do {
            let (data, response) = try await session.data(for: request)
            guard let httpResponse = response as? HTTPURLResponse else {
                throw JellyfinAPIError.invalidResponse
            }
            return (data, httpResponse)
        } catch let error as JellyfinAPIError {
            throw error
        } catch let error as URLError {
            if error.code == .cancelled {
                throw error
            }
            throw JellyfinAPIError.serverUnreachable
        }
    }

    private func authorizationHeaders(token: String? = nil) -> [String: String] {
        let device: String
        #if os(tvOS)
            device = "Apple TV"
        #elseif os(macOS)
            device = "Mac"
        #else
            device = "iPhone or iPad"
        #endif

        var authorization = "MediaBrowser Client=\"Strimr\", Device=\"\(device)\", DeviceId=\"\(deviceID)\", Version=\"\(clientVersion)\""
        let effectiveToken = token ?? accessToken
        if let effectiveToken {
            authorization += ", Token=\"\(effectiveToken)\""
        }
        var headers = ["Authorization": authorization]
        if let effectiveToken {
            headers["X-Emby-Token"] = effectiveToken
        }
        return headers
    }

    private func validateStatus(_ statusCode: Int) throws {
        switch statusCode {
        case 200 ..< 300:
            return
        case 401:
            authenticationRequiredHandler?()
            throw JellyfinAPIError.authenticationRequired
        case 403:
            throw JellyfinAPIError.permissionDenied
        case 404:
            throw JellyfinAPIError.itemUnavailable
        default:
            throw JellyfinAPIError.httpStatus(statusCode)
        }
    }

    private static func normalizedServerURL(_ value: String) throws -> URL {
        var normalized = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalized.isEmpty else { throw JellyfinAPIError.invalidServerURL }
        if !normalized.contains("://") {
            normalized = "http://\(normalized)"
        }
        guard var components = URLComponents(string: normalized),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host != nil,
              components.user == nil,
              components.password == nil
        else {
            throw JellyfinAPIError.invalidServerURL
        }
        components.scheme = scheme
        components.query = nil
        components.fragment = nil
        while components.path.count > 1, components.path.hasSuffix("/") {
            components.path.removeLast()
        }
        guard let url = components.url else { throw JellyfinAPIError.invalidServerURL }
        return url
    }

    private static func makeURL(
        baseURL: URL,
        path: [String],
        query: [URLQueryItem],
    ) throws -> URL {
        var url = baseURL
        for component in path {
            url.append(path: component)
        }
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw JellyfinAPIError.invalidServerURL
        }
        components.queryItems = query.isEmpty ? nil : query
        guard let result = components.url else { throw JellyfinAPIError.invalidServerURL }
        return result
    }

    private static func baseURL(fromResponseURL url: URL, removingPathComponents count: Int) -> URL {
        var result = url
        for _ in 0 ..< count {
            result.deleteLastPathComponent()
        }
        return result
    }
}

private final nonisolated class JellyfinRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection _: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void,
    ) {
        guard !Self.hasSameOrigin(task.currentRequest?.url, request.url) else {
            completionHandler(request)
            return
        }

        var sanitizedRequest = request
        sanitizedRequest.setValue(nil, forHTTPHeaderField: "Authorization")
        sanitizedRequest.setValue(nil, forHTTPHeaderField: "X-Emby-Token")
        completionHandler(sanitizedRequest)
    }

    private static func hasSameOrigin(_ lhs: URL?, _ rhs: URL?) -> Bool {
        guard let lhs, let rhs,
              let left = URLComponents(url: lhs, resolvingAgainstBaseURL: false),
              let right = URLComponents(url: rhs, resolvingAgainstBaseURL: false)
        else {
            return false
        }
        return left.scheme?.lowercased() == right.scheme?.lowercased()
            && left.host?.lowercased() == right.host?.lowercased()
            && effectivePort(left) == effectivePort(right)
    }

    private static func effectivePort(_ components: URLComponents) -> Int? {
        if let port = components.port {
            return port
        }
        switch components.scheme?.lowercased() {
        case "http": return 80
        case "https": return 443
        default: return nil
        }
    }
}
