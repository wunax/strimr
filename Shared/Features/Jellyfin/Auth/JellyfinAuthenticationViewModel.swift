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
    var discoveredServers: [JellyfinDiscoveredServer] = []
    var isLoading = false
    var isDiscovering = false
    var errorMessage: String?
    private(set) var isQuickConnectAvailable = false
    /// Code to approve from a signed-in Jellyfin client while Quick Connect is waiting.
    private(set) var quickConnectCode: String?

    var isBusy: Bool {
        isLoading || isDiscovering
    }

    @ObservationIgnored private let context = JellyfinAPIContext()
    @ObservationIgnored private let onAuthenticated: (JellyfinAuthenticatedSession, JellyfinConnection) throws -> Void
    @ObservationIgnored private let discoveryService = JellyfinServerDiscoveryService()
    @ObservationIgnored private var validatedServer: JellyfinPublicSystemInfo?
    @ObservationIgnored private var validatedBaseURL: URL?
    @ObservationIgnored private var quickConnectTask: Task<Void, Never>?

    /// - Parameter serverURL: prefills the server, e.g. to sign in again to a known server.
    init(
        serverURL: String = "",
        onAuthenticated: @escaping (JellyfinAuthenticatedSession, JellyfinConnection) throws -> Void,
    ) {
        self.serverURL = serverURL
        self.onAuthenticated = onAuthenticated
    }

    func validateServer() async {
        guard !isBusy else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        do {
            let (server, baseURL) = try await context.validateServerURL(serverURL)
            guard !Task.isCancelled else { return }
            validatedServer = server
            validatedBaseURL = baseURL
            serverName = server.serverName
            isQuickConnectAvailable = await context.isQuickConnectEnabled(baseURL: baseURL)
            step = .credentials
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            errorMessage = error.localizedDescription
        }
    }

    func discoverServers() async {
        guard !isBusy else { return }
        discoveredServers = []
        isDiscovering = true
        errorMessage = nil
        defer { isDiscovering = false }

        do {
            let servers = try await discoveryService.discover()
            guard !Task.isCancelled else { return }
            discoveredServers = servers
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = String(localized: "jellyfin.auth.discovery.error")
        }
    }

    func selectDiscoveredServer(_ server: JellyfinDiscoveredServer) async {
        guard !isBusy else { return }
        serverURL = server.url.absoluteString
        await validateServer()
    }

    func signIn() async {
        guard !isBusy,
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
            try onAuthenticated(authenticated, connection)
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

    // MARK: - Quick Connect

    func startQuickConnect() {
        guard let validatedServer, let validatedBaseURL, quickConnectTask == nil else { return }
        errorMessage = nil
        quickConnectTask = Task { [weak self] in
            guard let self else { return }
            defer {
                quickConnectTask = nil
                quickConnectCode = nil
            }
            do {
                var state = try await context.initiateQuickConnect(baseURL: validatedBaseURL)
                quickConnectCode = state.code
                while !state.authenticated {
                    try await Task.sleep(for: .seconds(3))
                    state = try await context.quickConnectState(baseURL: validatedBaseURL, secret: state.secret)
                }
                let (authenticated, connection) = try await context.authenticateWithQuickConnect(
                    server: validatedServer,
                    baseURL: validatedBaseURL,
                    secret: state.secret,
                )
                try onAuthenticated(authenticated, connection)
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                if (error as? JellyfinAPIError) != .serverUnreachable {
                    ErrorReporter.capture(error)
                }
                errorMessage = String(localized: "jellyfin.auth.quickConnect.error")
            }
        }
    }

    func cancelQuickConnect() {
        quickConnectTask?.cancel()
        quickConnectTask = nil
        quickConnectCode = nil
    }

    func goBack() {
        cancelQuickConnect()
        step = .server
        validatedServer = nil
        validatedBaseURL = nil
        serverName = ""
        password = ""
        errorMessage = nil
    }
}
