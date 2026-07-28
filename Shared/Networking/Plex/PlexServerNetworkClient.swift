import Foundation

struct PlexBinaryDownload: @unchecked Sendable {
    let temporaryFileURL: URL
    let response: HTTPURLResponse
}

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

    func download(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        acceptedStatusCodes: Set<Int> = Set(200 ..< 300),
    ) async throws -> PlexBinaryDownload {
        let request = try buildRequest(
            path: path,
            queryItems: queryItems,
            method: "GET",
            headers: headers,
        )
        let (downloadURL, response) = try await session.download(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard acceptedStatusCodes.contains(httpResponse.statusCode) else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
            .appendingPathExtension("download")
        try FileManager.default.moveItem(at: downloadURL, to: retainedURL)
        return PlexBinaryDownload(
            temporaryFileURL: retainedURL,
            response: httpResponse,
        )
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
