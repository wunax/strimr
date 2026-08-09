import AppKit
import AuthenticationServices
import Observation

@MainActor
@Observable
final class SignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationProvider = AuthenticationPresentationProvider()
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let context: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        self.context = context
    }

    func startSignIn() async {
        cancelSignIn()
        errorMessage = nil
        isAuthenticating = true

        do {
            let pin = try await AuthRepository(context: context).requestPin()
            guard await openAuthenticationURL(for: pin) else {
                throw SignInError.browserUnavailable
            }
            beginPolling(pinID: pin.id)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                cancelSignIn()
                return
            }
            errorMessage = String(localized: "signIn.error.startFailed")
            ErrorReporter.capture(error)
            cancelSignIn(keepingError: true)
        }
    }

    func cancelSignIn(keepingError: Bool = false) {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil
        authSession?.cancel()
        authSession = nil
        if !keepingError {
            errorMessage = nil
        }
    }

    private func openAuthenticationURL(for pin: PlexCloudPin) async -> Bool {
        guard let url = authenticationURL(for: pin) else { return false }

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            guard let authError = error as? ASWebAuthenticationSessionError,
                  authError.code == .canceledLogin
            else { return }
            Task { @MainActor in
                self?.cancelSignIn()
            }
        }
        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = presentationProvider
        authSession = session

        if session.start() {
            return true
        }

        authSession = nil
        return NSWorkspace.shared.open(url)
    }

    private func authenticationURL(for pin: PlexCloudPin) -> URL? {
        var components = URLComponents(string: "https://app.plex.tv/auth")
        components?.fragment = "?clientID=\(pin.clientIdentifier)&context[device][product]=Strimr&code=\(pin.code)"
        return components?.url
    }

    private func beginPolling(pinID: Int) {
        pollTask?.cancel()
        pollTask = Task { [weak self] in
            guard let self else { return }
            while !Task.isCancelled, isAuthenticating {
                do {
                    let result = try await AuthRepository(context: context).pollToken(pinId: pinID)
                    if let token = result.authToken {
                        try await sessionManager.signIn(with: token)
                        cancelSignIn()
                        return
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        errorMessage = String(localized: "signIn.error.pinExpired")
                        cancelSignIn(keepingError: true)
                        return
                    }
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    ErrorReporter.capture(error)
                }

                try? await Task.sleep(for: .seconds(2))
            }
        }
    }
}

private enum SignInError: Error {
    case browserUnavailable
}

private final class AuthenticationPresentationProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}
