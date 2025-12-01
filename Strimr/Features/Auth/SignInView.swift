import AuthenticationServices
import SwiftUI
import UIKit

struct SignInView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIManager.self) private var plexApi

    @State private var isAuthenticating = false
    @State private var errorMessage: String?
    @State private var pin: PlexCloudPin?
    @State private var pollTask: Task<Void, Never>?
    @State private var authSession: ASWebAuthenticationSession?
    private let presentationContextProvider = WebAuthenticationPresentationContextProvider()

    var body: some View {
        VStack(spacing: 24) {
            Spacer()

            VStack(spacing: 12) {
                if let appIcon {
                    Image(uiImage: appIcon)
                        .resizable()
                        .frame(width: 128, height: 128)
                }

                Text("signIn.title")
                    .multilineTextAlignment(.center)
                    .font(.largeTitle.bold())

                Text("signIn.subtitle")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
            }

            if let errorMessage {
                Text(errorMessage)
                    .foregroundStyle(.red)
            }

            Button {
                Task { await startSignIn() }
            } label: {
                HStack {
                    if isAuthenticating { ProgressView().tint(.white) }
                    Text(isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding()
                .background(.brandPrimary)
                .foregroundStyle(.brandPrimaryForeground)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .disabled(isAuthenticating)

            if isAuthenticating {
                Button("signIn.button.cancel") { cancelSignIn() }
                    .padding(.top, 4)
            }

            Spacer()
        }
        .padding(24)
    }
}

extension SignInView {
    private var appIcon: UIImage? {
        guard
            let icons = Bundle.main.infoDictionary?["CFBundleIcons"] as? [String: Any],
            let primaryIcon = icons["CFBundlePrimaryIcon"] as? [String: Any],
            let iconFiles = primaryIcon["CFBundleIconFiles"] as? [String],
            let iconName = iconFiles.last
        else {
            return nil
        }

        return UIImage(named: iconName)
    }

    private func plexAuthURL(pin: PlexCloudPin) -> URL {
        let base = "https://app.plex.tv/auth#?"
        let fragment =
            "clientID=\(pin.clientIdentifier)" +
            "&context[device][product]=Strimr" +
            "&code=\(pin.code)"

        return URL(string: base + fragment)!
    }

    @MainActor
    private func startSignIn() async {
        cancelSignIn()
        errorMessage = nil
        isAuthenticating = true

        do {
            let pinResponse = try await plexApi.cloud.requestPin()
            pin = pinResponse

            let url = plexAuthURL(pin: pinResponse)
            let startedSession = await openAuthSession(url)

            guard startedSession else {
                throw SignInError.authSessionFailed
            }

            beginPolling(pinID: pinResponse.id)

        } catch {
            errorMessage = String(localized: "signIn.error.startFailed", bundle: .main)
            cancelSignIn()
        }
    }

    @MainActor
    private func openAuthSession(_ url: URL) async -> Bool {
        authSession?.cancel()

        let session = ASWebAuthenticationSession(url: url, callbackURLScheme: nil) { _, error in
            if let authError = error as? ASWebAuthenticationSessionError,
               authError.code == .canceledLogin
            {
                Task { @MainActor in cancelSignIn() }
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

    @MainActor
    private func openInSystemBrowser(_ url: URL) async -> Bool {
        guard UIApplication.shared.canOpenURL(url) else { return false }

        return await withCheckedContinuation { continuation in
            UIApplication.shared.open(url, options: [:]) { success in
                continuation.resume(returning: success)
            }
        }
    }

    @MainActor
    private func beginPolling(pinID: Int) {
        pollTask?.cancel()

        pollTask = Task {
            while !Task.isCancelled && isAuthenticating {
                do {
                    let result = try await plexApi.cloud.pollToken(pinId: pinID)
                    if let token = result.authToken {
                        await sessionManager.signIn(with: token)
                        cancelSignIn()
                        return
                    }
                } catch {
                    // ignore errors, continue polling
                }

                try? await Task.sleep(nanoseconds: 2_000_000_000)
            }
        }
    }

    @MainActor
    private func cancelSignIn() {
        isAuthenticating = false
        pollTask?.cancel()
        pollTask = nil
        pin = nil

        authSession?.cancel()
        authSession = nil
    }
}

private enum SignInError: Error {
    case authSessionFailed
}

private final class WebAuthenticationPresentationContextProvider: NSObject, ASWebAuthenticationPresentationContextProviding {
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        if let keyWindow = UIApplication.shared.connectedScenes
            .compactMap({ $0 as? UIWindowScene })
            .flatMap({ $0.windows })
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
