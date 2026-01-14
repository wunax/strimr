import AuthenticationServices
import Foundation
import Observation
import UIKit

@MainActor
@Observable
final class SignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?
    var errorDetails: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationContextProvider = WebAuthenticationPresentationContextProvider()
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let plexContext: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        plexContext = context
    }

    func startSignIn() async {
        cancelSignIn()
        errorMessage = nil
        errorDetails = nil
        isAuthenticating = true

        do {
            let authRepository = AuthRepository(context: plexContext)
            let pinResponse = try await authRepository.requestPin()

            let url = plexAuthURL(pin: pinResponse)
            let startedSession = await openAuthSession(url)

            guard startedSession else {
                throw SignInError.authSessionFailed
            }

            beginPolling(pinID: pinResponse.id)

        } catch {
            errorMessage = AuthErrorMapper.signInMessage(for: error)
            errorDetails = String(describing: error)
            cancelSignIn()
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil

        authSession?.cancel()
        authSession = nil
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)!
    }

    private func openAuthSession(_ url: URL) async -> Bool {
        authSession?.cancel()

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { [weak self] _, error in
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin
            {
                Task { @MainActor in
                    self?.cancelSignIn()
                }
            }
        }

        session.prefersEphemeralWebBrowserSession = false
        session.presentationContextProvider = presentationContextProvider
        authSession = session

        if session.start() {
            return true
        }

        authSession = nil
        return await openInSystemBrowser(url)
    }

    private func openInSystemBrowser(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled, isAuthenticating {
                do {
                    let authRepository = AuthRepository(context: plexContext)
                    let result = try await authRepository.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        do {
                            try await sessionManager.signIn(with: token)
                            cancelSignIn()
                            return
                        } catch {
                            errorMessage = AuthErrorMapper.signInMessage(for: error)
                            errorDetails = String(describing: error)
                            cancelSignIn()
                        }
                    }
                } catch {
                    errorMessage = AuthErrorMapper.signInMessage(for: error)
                    errorDetails = String(describing: error)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }
}

private enum SignInError: Error {
    case authSessionFailed
}

private final class WebAuthenticationPresentationContextProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap(\.windows)
            .first(where: { $0.isKeyWindow })
        {
            return keyWindow
        }

        if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
            return ASPresentationAnchor(windowScene: scene)
        }

        return ASPresentationAnchor()
    }
}
