import Foundation
import Observation

@MainActor
@Observable
final class JellyfinAuthenticationViewModel {
    enum Step {
        case server
        case credentials
    }

    var step: Step = .server
    var serverURL = ""
    var username = ""
    var password = ""
    var serverName = ""
    var isLoading = false
    var errorMessage: String?

    @ObservationIgnored private let context: JellyfinAPIContext
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private var validatedServer: JellyfinPublicSystemInfo?
    @ObservationIgnored private var validatedBaseURL: URL?

    init(context: JellyfinAPIContext, sessionManager: SessionManager) {
        self.context = context
        self.sessionManager = sessionManager
        errorMessage = sessionManager.jellyfinHydrationError
    }

    func validateServer() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (server, baseURL) = try await context.validateServerURL(serverURL)
            guard !Task.isCancelled else { return }
            validatedServer = server
            validatedBaseURL = baseURL
            serverName = server.serverName
            step = .credentials
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func signIn() async {
        guard !isLoading,
              let validatedServer,
              let validatedBaseURL,
              !username.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else {
            return
        }
        isLoading = true
        errorMessage = nil
        let submittedPassword = password
        password = ""
        defer { isLoading = false }
        do {
            let (authenticated, connection) = try await context.authenticate(
                server: validatedServer,
                baseURL: validatedBaseURL,
                username: username.trimmingCharacters(in: .whitespacesAndNewlines),
                password: submittedPassword,
            )
            try sessionManager.completeJellyfinSignIn(
                authenticatedSession: authenticated,
                connection: connection,
            )
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if (error as? JellyfinAPIError) != .invalidCredentials,
               (error as? JellyfinAPIError) != .serverUnreachable
            {
                ErrorReporter.capture(error)
            }
            errorMessage = error.localizedDescription
        }
    }

    func goBack() {
        step = .server
        validatedServer = nil
        validatedBaseURL = nil
        serverName = ""
        password = ""
        errorMessage = nil
    }
}
