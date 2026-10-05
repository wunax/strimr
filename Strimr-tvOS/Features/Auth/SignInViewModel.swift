import Foundation
import Observation

@MainActor
@Observable
final class SignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?
    var pin: PlexCloudPin?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private let onToken: (String) async throws -> Void
    @ObservationIgnored private let plexContext = PlexAPIContext()

    init(onToken: @escaping (String) async throws -> Void) {
        self.onToken = onToken
    }

    func startSignIn() async {
        resetSignInState()
        errorMessage = nil
        isAuthenticating = true

        do {
            try await requestNewPinAndBeginPolling()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else {
                cancelSignIn()
                return
            }
            errorMessage = String(localized: "signIn.error.startFailed")
            ErrorReporter.capture(error)
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
                            try await onToken(token)
                            cancelSignIn()
                            return
                        } catch {
                            guard !Task.isCancelled, !error.isCancellation else { return }
                            errorMessage = String(localized: "signIn.error.startFailed")
                            ErrorReporter.capture(error)
                            cancelSignIn()
                        }
                    }
                } catch {
                    if case PlexAPIError.requestFailed(statusCode: 404) = error {
                        do {
                            try await requestNewPinAndBeginPolling()
                            return
                        } catch {
                            guard !Task.isCancelled, !error.isCancellation else { return }
                            errorMessage = String(localized: "signIn.error.startFailed")
                            ErrorReporter.capture(error)
                            cancelSignIn()
                            return
                        }
                    }

                    guard !Task.isCancelled, !error.isCancellation else { return }
                    errorMessage = String(localized: "signIn.error.startFailed")
                    ErrorReporter.capture(error)
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    private func requestNewPinAndBeginPolling() async throws {
        await plexContext.waitForBootstrap()
        let authRepository = AuthRepository(context: plexContext)
        let pinResponse = try await authRepository.requestPin()
        pin = pinResponse
        beginPolling(pinID: pinResponse.id)
    }

    private func resetSignInState() {
        pollTask?.cancel()
        pollTask = nil
        pin = nil
    }
}
