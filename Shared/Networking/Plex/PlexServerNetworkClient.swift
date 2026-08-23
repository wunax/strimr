import Foundation

struct PlexBinaryDownload: @unchecked Sendable {
    let temporaryFileURL: URL
    let response: HTTPURLResponse
}

final class PlexServerNetworkClient {
    private let session: URLSession = .shared
    private weak var context: PlexAPIContext?
    private var language: String
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

    init(context: PlexAPIContext, language: String = "en") {
        self.context = context
        self.language = Locale.preferredLanguages.first ?? language
    }

    func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws -> Response {
        let result = try await data(
            path: path,
            queryItems: queryItems,
            method: method,
            headers: headers,
        )
        let data = result.data
        let response = result.response
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
        let result = try await data(
            path: path,
            queryItems: queryItems,
            method: method,
            headers: headers,
        )
        let response = result.response
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }

    func json(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) async throws -> [String: Any] {
        let result = try await data(
            path: path,
            queryItems: queryItems,
            method: method,
            headers: headers,
        )
        guard let response = result.response as? HTTPURLResponse,
              200 ..< 300 ~= response.statusCode
        else {
            throw PlexAPIError.requestFailed(
                statusCode: (result.response as? HTTPURLResponse)?.statusCode ?? -1,
            )
        }
        guard let object = try JSONSerialization.jsonObject(with: result.data) as? [String: Any] else {
            throw PlexAPIError.invalidResponse
        }
        return object
    }

    func download(
        path: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        acceptedStatusCodes: Set<Int> = Set(200 ..< 300),
    ) async throws -> PlexBinaryDownload {
        let result = try await download(
            path: path,
            queryItems: queryItems,
            headers: headers,
        )
        let downloadURL = result.url
        let response = result.response
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

    private func data(
        path: String,
        queryItems: [URLQueryItem]?,
        method: String,
        headers: [String: String],
    ) async throws -> (data: Data, response: URLResponse) {
        let context = try requireContext()
        let snapshot = try context.serverAccessSnapshot()
        let request = try buildRequest(
            snapshot: snapshot,
            path: path,
            queryItems: queryItems,
            method: method,
            headers: headers,
        )
        let result = try await session.data(for: request)
        guard (result.1 as? HTTPURLResponse)?.statusCode == 401 else {
            return result
        }

        try await context.recoverServerAccess(afterUnauthorizedSnapshot: snapshot)
        let refreshedSnapshot = try context.serverAccessSnapshot()
        let retryRequest = try buildRequest(
            snapshot: refreshedSnapshot,
            path: path,
            queryItems: queryItems,
            method: method,
            headers: headers,
        )
        return try await session.data(for: retryRequest)
    }

    private func download(
        path: String,
        queryItems: [URLQueryItem]?,
        headers: [String: String],
    ) async throws -> (url: URL, response: URLResponse) {
        let context = try requireContext()
        let snapshot = try context.serverAccessSnapshot()
        let request = try buildRequest(
            snapshot: snapshot,
            path: path,
            queryItems: queryItems,
            method: "GET",
            headers: headers,
        )
        let result = try await session.download(for: request)
        guard (result.1 as? HTTPURLResponse)?.statusCode == 401 else {
            return result
        }

        try? FileManager.default.removeItem(at: result.0)
        try await context.recoverServerAccess(afterUnauthorizedSnapshot: snapshot)
        let refreshedSnapshot = try context.serverAccessSnapshot()
        let retryRequest = try buildRequest(
            snapshot: refreshedSnapshot,
            path: path,
            queryItems: queryItems,
            method: "GET",
            headers: headers,
        )
        return try await session.download(for: retryRequest)
    }

    private func requireContext() throws -> PlexAPIContext {
        guard let context else {
            throw PlexAPIError.missingConnection
        }
        return context
    }

    private func buildRequest(
        snapshot: PlexAPIContext.ServerAccessSnapshot,
        path: String,
        queryItems: [URLQueryItem]? = nil,
        method: String = "GET",
        headers: [String: String] = [:],
    ) throws -> URLRequest {
        guard var components = URLComponents(
            url: snapshot.baseURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false,
        )
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
        request.setValue(snapshot.authToken, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(language, forHTTPHeaderField: "X-Plex-Language")
        request.setValue(snapshot.clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        for (key, value) in headers {
            request.setValue(value, forHTTPHeaderField: key)
        }

        return request
    }
}
