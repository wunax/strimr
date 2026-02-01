import Foundation

final class SeerrNetworkClient {
    private let session: URLSession
    private let baseURL: URL

    init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
    ) async throws -> Response {
        try await request(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Never?.none,
        )
    }

    func request<Response: Decodable>(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (some Encodable)? = nil,
    ) async throws -> Response {
        let request = try buildRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
        )

        let (data, response) = try await session.data(for: request)
        try validateResponse(response)

        do {
            return try JSONDecoder().decode(Response.self, from: data)
        } catch {
            throw SeerrAPIError.decodingFailed(error)
        }
    }

    func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
    ) async throws {
        try await send(
            path: path,
            method: method,
            queryItems: queryItems,
            body: Never?.none,
        )
    }

    func send(
        path: String,
        method: String = "GET",
        queryItems: [URLQueryItem]? = nil,
        body: (some Encodable)? = nil,
    ) async throws {
        let request = try buildRequest(
            path: path,
            queryItems: queryItems,
            method: method,
            body: body,
        )

        let (_, response) = try await session.data(for: request)
        try validateResponse(response)
    }

    private func buildRequest(
        path: String,
        queryItems: [URLQueryItem]?,
        method: String,
        body: (some Encodable)?,
    ) throws -> URLRequest {
        let cleanedPath = path.hasPrefix("/") ? String(path.dropFirst()) : path
        let apiBase = baseURL.appendingPathComponent("api/v1")
        let url = apiBase.appendingPathComponent(cleanedPath)
        let resolvedURL = try resolveURL(url, queryItems: queryItems)

        var request = URLRequest(url: resolvedURL)
        request.httpMethod = method
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        if let body {
            request.httpBody = try JSONEncoder().encode(body)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        return request
    }

    private func resolveURL(_ url: URL, queryItems: [URLQueryItem]?) throws -> URL {
        guard let queryItems, !queryItems.isEmpty else {
            return url
        }

        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw SeerrAPIError.invalidURL
        }

        components.queryItems = queryItems

        guard let resolvedURL = components.url else {
            throw SeerrAPIError.invalidURL
        }

        return resolvedURL
    }

    private func validateResponse(_ response: URLResponse) throws {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw SeerrAPIError.requestFailed(statusCode: -1)
        }
        guard 200 ..< 300 ~= httpResponse.statusCode else {
            throw SeerrAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }
    }
}
