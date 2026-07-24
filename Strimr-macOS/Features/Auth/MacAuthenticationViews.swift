import AppKit
import AuthenticationServices
import Observation
import SwiftUI

@MainActor
@Observable
final class MacSignInViewModel {
    var isAuthenticating = false
    var errorMessage: String?

    @ObservationIgnored private var pollTask: Task<Void, Never>?
    @ObservationIgnored private var authSession: ASWebAuthenticationSession?
    @ObservationIgnored private let presentationProvider = MacAuthenticationPresentationProvider()
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
                throw MacSignInError.browserUnavailable
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

private enum MacSignInError: Error {
    case browserUnavailable
}

private final class MacAuthenticationPresentationProvider: NSObject,
    ASWebAuthenticationPresentationContextProviding
{
    func presentationAnchor(for _: ASWebAuthenticationSession) -> ASPresentationAnchor {
        NSApp.keyWindow ?? NSApp.windows.first ?? NSWindow()
    }
}

struct MacSignInView: View {
    @State private var viewModel: MacSignInViewModel

    init(viewModel: MacSignInViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image("Icon")
                .resizable()
                .scaledToFit()
                .frame(width: 136, height: 136)
                .clipShape(RoundedRectangle(cornerRadius: 28, style: .continuous))

            VStack(spacing: 8) {
                Text("signIn.title")
                    .font(.largeTitle.bold())
                Text("signIn.subtitle")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task { await viewModel.startSignIn() }
            } label: {
                HStack(spacing: 10) {
                    if viewModel.isAuthenticating {
                        ProgressView().controlSize(.small)
                    }
                    Text(viewModel.isAuthenticating ? "signIn.button.waiting" : "signIn.button.continue")
                }
                .frame(width: 260)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(viewModel.isAuthenticating)

            if viewModel.isAuthenticating {
                Button("signIn.button.cancel") {
                    viewModel.cancelSignIn()
                }
                .buttonStyle(.link)
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onDisappear { viewModel.cancelSignIn() }
    }
}

struct MacProfileSwitcherView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinUser: PlexHomeUser?
    @State private var pin = ""
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("auth.profile.header.title")
                        .font(.largeTitle.bold())
                    Text("auth.profile.header.subtitle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isShowingLogoutConfirmation = true
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading, viewModel.users.isEmpty {
                ProgressView("auth.profile.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 24)], spacing: 24) {
                        ForEach(viewModel.users) { user in
                            profileButton(for: user)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(32)
        .task { await viewModel.loadUsers() }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .sheet(item: $pinUser) { user in
            VStack(alignment: .leading, spacing: 16) {
                Text("auth.profile.pin.title").font(.headline)
                Text("auth.profile.pin.prompt \(user.friendlyName ?? user.title ?? "?")")
                    .foregroundStyle(.secondary)
                SecureField("auth.profile.pin.placeholder", text: $pin)
                    .frame(width: 240)
                    .onSubmit { submitPin(for: user) }
                HStack {
                    Button("common.actions.cancel", role: .cancel) {
                        pinUser = nil
                    }
                    Spacer()
                    Button("signIn.button.continue") {
                        submitPin(for: user)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }

    private func profileButton(for user: PlexHomeUser) -> some View {
        Button {
            if user.protected == true {
                pin = ""
                pinUser = user
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 10) {
                AsyncImage(url: user.thumb) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.square.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if user.protected == true {
                        Image(systemName: "lock.fill").padding(8)
                    }
                }
                Text(user.friendlyName ?? user.title ?? "?")
                    .font(.headline)
                    .lineLimit(1)
                if viewModel.switchingUserUUID == user.uuid {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingUserUUID != nil)
    }

    private func submitPin(for user: PlexHomeUser) {
        let submittedPin = pin
        pinUser = nil
        pin = ""
        Task { await viewModel.switchToUser(user, pin: submittedPin) }
    }
}

struct MacServerSelectionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ServerSelectionViewModel
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ServerSelectionViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("serverSelection.title").font(.largeTitle.bold())
                    Text("serverSelection.subtitle").foregroundStyle(.secondary)
                }
                Spacer()
                Button("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isShowingLogoutConfirmation = true
                }
            }

            if viewModel.isLoading, viewModel.servers.isEmpty {
                ProgressView("serverSelection.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if viewModel.servers.isEmpty {
                ContentUnavailableView {
                    Label("serverSelection.empty.title", systemImage: "server.rack")
                } description: {
                    Text("serverSelection.empty.description")
                } actions: {
                    Button("serverSelection.retry") {
                        Task { await viewModel.load() }
                    }
                }
            } else {
                List(viewModel.servers, id: \.clientIdentifier) { server in
                    Button {
                        Task { await viewModel.select(server: server) }
                    } label: {
                        HStack(spacing: 14) {
                            Image(systemName: "server.rack")
                                .font(.title2)
                                .foregroundStyle(.brandPrimary)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(server.name).font(.headline)
                                Text(connectionDescription(for: server))
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if viewModel.selectingServerID == server.clientIdentifier {
                                ProgressView().controlSize(.small)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .disabled(viewModel.isSelecting)
                    .padding(.vertical, 5)
                }
            }
        }
        .padding(32)
        .task { await viewModel.load() }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .alert("serverSelection.error.connection.title", isPresented: $viewModel.isShowingSelectionError) {
            Button("common.actions.retry") { viewModel.requestSelectionRetry() }
            Button("common.actions.cancel", role: .cancel) { viewModel.dismissSelectionError() }
        } message: {
            Text("serverSelection.error.connection.message")
        }
        .onChange(of: viewModel.isShowingSelectionError) { _, isPresented in
            guard !isPresented else { return }
            Task { await viewModel.retrySelectionAfterAlertDismissal() }
        }
    }

    private func connectionDescription(for server: PlexCloudResource) -> String {
        guard let connection = server.connections?.first else {
            return String(localized: "serverSelection.connection.unavailable")
        }
        if connection.isLocal {
            return String(localized: "serverSelection.connection.localFormat \(connection.address)")
        }
        if connection.isRelay {
            return String(localized: "serverSelection.connection.relay")
        }
        return connection.address
    }
}
