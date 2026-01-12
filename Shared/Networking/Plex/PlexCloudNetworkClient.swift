import Foundation

final class PlexCloudNetworkClient {
    private let session: URLSession = .shared
    private let baseURL: URL
    private let apiURL = URL(string: "https://plex.tv/api/v2")!
    private let discoverBaseURL = URL(string: "https://discover.provider.plex.tv")!
    private var authToken: String?
    private var clientIdentifier: String
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private let platform: String = {
        #if os(tvOS)
            return "tvOS"
        #elseif os(iOS)
            return "iOS"
        #else
            return "Unknown"
        #endif
    }()

    init(authToken: String?, clientIdentifier: String, useDiscoverBaseURL: Bool = false) {
        self.authToken = authToken
        self.clientIdentifier = clientIdentifier
        baseURL = useDiscoverBaseURL ? discoverBaseURL : apiURL
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
    ) async throws -> Response {
        let request = try buildRequest(path: path, method: method, queryItems: queryItems, headers: headers, body: body)

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil,
    ) async throws {
        let request = try buildRequest(path: path, method: method, queryItems: queryItems, headers: headers, body: body)

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    private func buildRequest(
        path: String,
        method: String,
        queryItems: [URLQueryItem]?,
        headers: [String: String],
        body: Data?,
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else {
            throw PlexAPIError.invalidURL
        }
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let resolvedURL = components.url else {
            throw PlexAPIError.invalidURL
        }

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(platform, forHTTPHeaderField: "X-Plex-Platform")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
        }
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        if let authToken {
            request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
