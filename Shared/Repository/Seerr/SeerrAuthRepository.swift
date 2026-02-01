import Foundation

final class SeerrAuthRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func checkStatus() async throws {
        try await client.send(path: "status")
    }

    func signInWithPlex(authToken: String) async throws {
        try await client.send(
            path: "auth/plex",
            method: "POST",
            body: SeerrPlexAuthRequest(authToken: authToken),
        )
    }

    func signInWithLocal(email: String, password: String) async throws {
        try await client.send(
            path: "auth/local",
            method: "POST",
            body: SeerrLocalAuthRequest(email: email, password: password),
        )
    }

    func fetchCurrentUser() async throws -> SeerrUser {
        try await client.request(path: "auth/me")
    }

    func fetchQuota(userId: Int) async throws -> SeerrUserQuota {
        try await client.request(path: "user/\(userId)/quota")
    }
}
