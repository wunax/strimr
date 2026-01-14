import Foundation
import Observation

@MainActor
@Observable
final class SignInTVViewModel {
    var isAuthenticating = false
    var errorMessage: String?
    var errorDetails: String?
    var pin: PlexCloudPin?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let plexContext: PlexAPIContext

    init(sessionManager: SessionManager, context: PlexAPIContext) {
        self.sessionManager = sessionManager
        plexContext = context
    }

    func startSignIn() async {
        resetSignInState()
        errorMessage = nil
        errorDetails = nil
        isAuthenticating = true

        do {
            let authRepository = AuthRepository(context: plexContext)
            let pinResponse = try await authRepository.requestPin()
            pin = pinResponse
            beginPolling(pinID: pinResponse.id)
        } catch {
            errorMessage = AuthErrorMapper.signInMessage(for: error)
            errorDetails = String(describing: error)
            isAuthenticating = false
        }
    }

    func cancelSignIn() {
        isAuthenticating = false
        resetSignInState()
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

    private func resetSignInState() {
        pollTask?.cancel()
        pollTask = nil
        pin = nil
    }
}
