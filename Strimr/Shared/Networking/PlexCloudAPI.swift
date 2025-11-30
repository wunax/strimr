import Foundation

enum PlexAPIError: Error {
    case invalidURL
    case missingConnection
    case unreachableServer
    case requestFailed(statusCode: Int)
    case decodingFailed(Error)
}

final class PlexCloudAPI {
    private let baseURL = URL(string: "https://plex.tv/api/v2")!
    private var clientIdentifier: String?
    private var authToken: String?
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func setClientIdentifier(_ clientIdentifier: String) {
        self.clientIdentifier = clientIdentifier
    }
    
    func setAuthToken(_ authToken: String?) {
        self.authToken = authToken
    }
    
    func requestPin() async throws -> PlexCloudPin {
        try await request(
            path: "/pins",
            method: "POST",
            queryItems: [URLQueryItem(name: "strong", value: "true")],
            headers: ["X-Plex-Product": "Strimr"]
        )
    }

    func pollToken(pinId: Int) async throws -> PlexCloudPin {
        try await request(path: "/pins/\(pinId)", method: "GET")
    }

    func getUser() async throws -> PlexCloudUser {
        try await request(path: "/user", method: "GET")
    }

    func getResources() async throws -> [PlexCloudResource] {
        try await request(path: "/resources", method: "GET")
    }

    private func request<Response: Decodable>(
        path: String,
        method: String,
        queryItems: [URLQueryItem]? = nil,
        headers: [String: String] = [:],
        body: Data? = nil
    ) async throws -> Response {
        guard var components = URLComponents(url: baseURL.appendingPathComponent(path), resolvingAgainstBaseURL: false) else {
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
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue(clientIdentifier, forHTTPHeaderField: "X-Plex-Client-Identifier")
        if let authToken {
            request.setValue(authToken, forHTTPHeaderField: "X-Plex-Token")
        }
        headers.forEach { key, value in
            request.setValue(value, forHTTPHeaderField: key)
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw PlexAPIError.requestFailed(statusCode: -1)
        }
        guard 200..<300 ~= httpResponse.statusCode else {
            throw PlexAPIError.requestFailed(statusCode: httpResponse.statusCode)
        }

        do {
            let decoder = JSONDecoder()
            return try decoder.decode(Response.self, from: data)
        } catch {
            throw PlexAPIError.decodingFailed(error)
        }
    }
}
