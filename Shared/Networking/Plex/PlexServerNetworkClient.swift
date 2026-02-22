import Foundation

final class PlexServerNetworkClient {
    private let session: URLSession = .shared
    private var authToken: String
    private var baseURL: URL
    private var language: String
    private var clientIdentifier: String?
    private let appVersion = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
    private let platform: String = {
        #if os(tvOS)
            return "tvOS"
        #elseif os(visionOS)
            return "visionOS"
        #elseif os(iOS)
            return "iOS"
        #else
            return "Unknown"
        #endif
    }()

    init(authToken: String, baseURL: URL, clientIdentifier: String? = nil, language: String = "en") {
        self.authToken = authToken
        self.baseURL = baseURL
        self.language = Locale.preferredLanguages.first ?? language
        self.clientIdentifier = clientIdentifier
    }

    func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws -> Response {
        let request = try buildRequest(path: path, queryItems: queryItems, method: method, headers: headers)

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
            debugPrint(error)
            throw PlexAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws {
        let request = try buildRequest(path: path, queryItems: queryItems, method: method, headers: headers)

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
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) throws -> URLRequest {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false)
        else {
            throw PlexAPIError.invalidURL
        }
        if let queryItems {
            components.queryItems = queryItems
        }
        guard let url = components.url else {
            throw PlexAPIError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue(platform, forHTTPHeaderField: "X-Plex-Platform")
        if let appVersion {
            request.setValue(appVersion, forHTTPHeaderField: "X-Plex-Version")
        }
        request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(language, forHTTPHeaderField: "X-Plex-Language")
        if let clientIdentifier {
            request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        }
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
