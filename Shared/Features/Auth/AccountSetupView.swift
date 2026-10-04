import SwiftUI

/// Hosts `AccountSetupFlow`: provider choice, sign-in, Plex Home user, server choice and, at first launch, the
/// optional "add another account" step.
struct AccountSetupView: View {
    @State private var flow: AccountSetupFlow
    private let onFinished: () -> Void

    init(purpose: AccountSetupFlow.Purpose, sessionManager: SessionManager, onFinished: @escaping () -> Void = {}) {
        _flow = State(initialValue: AccountSetupFlow(purpose: purpose, sessionManager: sessionManager))
        self.onFinished = onFinished
    }

    var body: some View {
        NavigationStack(path: $flow.path) {
            ProviderSelectionView(onSelect: flow.choose)
                .safeAreaInset(edge: .bottom) {
                    if flow.canFinishFromProviderChoice {
                        Button("common.actions.continue") {
                            Task { await flow.finish() }
                        }
                        .buttonStyle(.borderedProminent)
                        .tint(.brandPrimary)
                        .padding()
                    }
                }
                .toolbar {
                    if flow.purpose != .firstLaunch {
                        ToolbarItem(placement: .cancellationAction) {
                            Button("common.actions.cancel") { flow.cancel() }
                        }
                    }
                }
                .navigationDestination(for: AccountSetupFlow.Step.self, destination: destination)
        }
        .onChange(of: flow.isFinished) { _, isFinished in
            if isFinished {
                onFinished()
            }
        }
        .onDisappear {
            if !flow.isFinished, flow.purpose != .firstLaunch {
                flow.cancel()
            }
        }
    }

    @ViewBuilder
    private func destination(_ step: AccountSetupFlow.Step) -> some View {
        switch step {
        case .plexSignIn:
            SignInView(viewModel: SignInViewModel(onToken: { token in
                try await flow.plexSignedIn(token: token)
            }))
        case .jellyfin:
            JellyfinAuthenticationView(viewModel: JellyfinAuthenticationViewModel { session, connection in
                try flow.jellyfinSignedIn(session: session, connection: connection)
            })
        case let .plexHomeUser(accountID):
            ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(
                sessionManager: flow.sessionManager,
                mode: .chooseHomeUser(accountID: accountID) { uuid, token in
                    await flow.plexHomeUserChosen(accountID: accountID, userUUID: uuid, token: token)
                },
            ))
        case let .plexServers(accountID, userUUID):
            SelectServerView(viewModel: ServerSelectionViewModel(
                loadServers: { try await flow.sessionManager.plexServers(accountID: accountID, userUUID: userUUID) },
                onContinue: { disabled in
                    flow.plexServersChosen(accountID: accountID, userUUID: userUUID, disabledServerIDs: disabled)
                },
            ))
        case .addAnotherAccount:
            AddAnotherAccountView(
                onAddAccount: flow.addAnotherAccount,
                onContinue: { Task { await flow.finish() } },
            )
        }
    }
}

/// Optional last step of the first launch.
struct AddAnotherAccountView: View {
    let onAddAccount: () -> Void
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Spacer()
            Image(systemName: "person.2.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.brandPrimary)
            Text("onboarding.addAnother.title")
                .font(.largeTitle.bold())
                .multilineTextAlignment(.center)
            Text("onboarding.addAnother.subtitle")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 560)
            Button(action: onContinue) {
                Text("common.actions.continue")
                    .fontWeight(.semibold)
                    .frame(maxWidth: 420)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            .tint(.brandPrimary)
            .controlSize(.large)
            Button("onboarding.addAnother.button", action: onAddAccount)
                .controlSize(.large)
            Spacer()
        }
        .padding(32)
        .navigationBarBackButtonHidden()
    }
}
