import Foundation

final class SeerrSessionService {
    func validateServer(urlString: String) async throws -> URL {
        let trimmed = urlString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), url.scheme != nil, url.host != nil else {
            throw SeerrAPIError.invalidURL
        }

        let repository = SeerrAuthRepository(baseURL: url)
        try await repository.checkStatus()
        return url
    }

    func signInWithPlex(baseURL: URL, authToken: String) async throws -> SeerrUser {
        let repository = SeerrAuthRepository(baseURL: baseURL)
        try await repository.signInWithPlex(authToken: authToken)
        return try await repository.fetchCurrentUser()
    }

    func signInWithLocal(baseURL: URL, email: String, password: String) async throws -> SeerrUser {
        let repository = SeerrAuthRepository(baseURL: baseURL)
        try await repository.signInWithLocal(email: email, password: password)
        return try await repository.fetchCurrentUser()
    }

    func hydrateCurrentUser(baseURL: URL) async throws -> SeerrUser {
        let repository = SeerrAuthRepository(baseURL: baseURL)
        return try await repository.fetchCurrentUser()
    }

    func signOut(baseURL: URL) {
        let cookieStorage = HTTPCookieStorage.shared
        cookieStorage.cookies(for: baseURL)?.forEach { cookieStorage.deleteCookie($0) }
    }
}
