import Foundation
import Observation

@MainActor
@Observable
final class SeerrViewModel {
    @ObservationIgnored private let store: SeerrStore
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let sessionService: SeerrSessionService

    var baseURLInput = ""
    var email = ""
    var password = ""
    var errorMessage = ""
    var isShowingError = false
    var isValidating = false
    var isAuthenticating = false

    init(store: SeerrStore, sessionManager: SessionManager, sessionService: SeerrSessionService) {
        self.store = store
        self.sessionManager = sessionManager
        self.sessionService = sessionService
        baseURLInput = store.baseURLString ?? ""
    }

    func validateServer() async {
        isValidating = true
        defer { isValidating = false }

        do {
            let url = try await sessionService.validateServer(urlString: baseURLInput)
            store.setBaseURL(url.absoluteString)
        } catch {
            presentError(error)
        }
    }

    func signInWithPlex() async {
        guard let authToken = sessionManager.authToken else { return }

        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let baseURL = try requireBaseURL()
            let user = try await sessionService.signInWithPlex(baseURL: baseURL, authToken: authToken)
            store.setUser(user)
        } catch {
            presentError(error)
        }
    }

    func signInWithLocal() async {
        isAuthenticating = true
        defer { isAuthenticating = false }

        do {
            let baseURL = try requireBaseURL()
            let user = try await sessionService.signInWithLocal(baseURL: baseURL, email: email, password: password)
            store.setUser(user)
            password = ""
        } catch {
            presentError(error)
        }
    }

    func signOut() {
        if let baseURL = baseURL {
            sessionService.signOut(baseURL: baseURL)
        }
        store.clearUser()
    }

    var user: SeerrUser? {
        store.user
    }

    var baseURLString: String? {
        store.baseURLString
    }

    var isLoggedIn: Bool {
        store.isLoggedIn
    }

    var isPlexAuthAvailable: Bool {
        sessionManager.authToken != nil
    }

    private var baseURL: URL? {
        guard let baseURLString = store.baseURLString else { return nil }
        return URL(string: baseURLString)
    }

    private func requireBaseURL() throws -> URL {
        guard let baseURL else { throw SeerrAPIError.invalidURL }
        return baseURL
    }

    private func presentError(_ error: Error) {
        let key = switch error {
        case SeerrAPIError.invalidURL:
            "integrations.seerr.error.invalidURL"
        case SeerrAPIError.requestFailed:
            "integrations.seerr.error.connection"
        default:
            "common.errors.tryAgainLater"
        }

        errorMessage = String(localized: .init(key))
        isShowingError = true
    }
}
