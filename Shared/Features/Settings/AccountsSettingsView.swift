import SwiftUI

/// "Accounts and servers": the accounts of the app and, for the active profile, the activation and status of each
/// server.
struct AccountsSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    #if !os(tvOS)
        @Environment(DownloadManager.self) private var downloadManager
        @State private var removalFlow = AccountRemovalFlow()
    #endif
    @State private var isAddingAccount = false
    @State private var accountPendingRemoval: MediaAccount?
    @State private var reconnectingAccount: MediaAccount?

    var body: some View {
        List {
            ForEach(sessionManager.accounts) { account in
                Section {
                    accountContent(account)
                } header: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(account.displayName)
                        Text(account.provider == .plex ? "provider.plex" : "provider.jellyfin")
                            .font(.caption)
                    }
                } footer: {
                    if sessionManager.isAccountUnused(account.id) {
                        Text("settings.accounts.unused")
                    }
                }
            }

            Section {
                Button("settings.accounts.add") { isAddingAccount = true }
            }
        }
        .navigationTitle("settings.accounts.title")
        .sheet(isPresented: $isAddingAccount) {
            AccountSetupView(purpose: .settings, sessionManager: sessionManager) {
                isAddingAccount = false
            }
        }
        .sheet(item: $reconnectingAccount) { account in
            NavigationStack {
                ReconnectAccountView(account: account) { reconnectingAccount = nil }
            }
        }
        .alert(
            "settings.accounts.remove.title",
            isPresented: Binding(
                get: { accountPendingRemoval != nil },
                set: {
                    if !$0 {
                        accountPendingRemoval = nil
                    }
                },
            ),
            presenting: accountPendingRemoval,
        ) { account in
            Button("settings.accounts.remove", role: .destructive) { remove(account) }
            Button("common.actions.cancel", role: .cancel) {}
        } message: { account in
            Text("settings.accounts.remove.message \(account.displayName)")
        }
        #if !os(tvOS)
        .accountRemovalPrompt(removalFlow)
        #endif
    }

    @ViewBuilder
    private func accountContent(_ account: MediaAccount) -> some View {
        let sessions = sessionManager.registry.sessions(accountID: account.id)
        if sessions.isEmpty {
            Text(isLinkedToActiveProfile(account) ? "settings.accounts.noServers" : "settings.accounts.notLinked")
                .foregroundStyle(.secondary)
        }
        ForEach(sessions) { session in
            ServerSessionRow(session: session) { enabled in
                sessionManager.registry.setEnabled(enabled, server: session.identity)
            }
            if session.status == .needsReauthentication {
                Button("settings.accounts.reconnect") { reconnectingAccount = account }
            }
        }
        if sessionManager.registry.linkStatuses[account.id] == .needsReauthentication, sessions.isEmpty {
            Button("settings.accounts.reconnect") { reconnectingAccount = account }
        }
        Button("settings.accounts.remove", role: .destructive) { accountPendingRemoval = account }
    }

    private func isLinkedToActiveProfile(_ account: MediaAccount) -> Bool {
        guard let profile = sessionManager.activeProfile else { return false }
        return sessionManager.links(for: profile).contains { $0.accountID == account.id }
    }

    private func remove(_ account: MediaAccount) {
        #if os(tvOS)
            sessionManager.removeAccount(account.id)
        #else
            Task {
                await removalFlow.begin(
                    accountID: account.id,
                    sessionManager: sessionManager,
                    downloadManager: downloadManager,
                )
            }
        #endif
    }
}

/// A server of the active profile: activation for this profile only, and its status.
struct ServerSessionRow: View {
    let session: ServerSession
    let onToggle: (Bool) -> Void

    var body: some View {
        Toggle(isOn: Binding(get: { session.isEnabled }, set: onToggle)) {
            VStack(alignment: .leading, spacing: 2) {
                Text(session.name)
                Text(statusTitle)
                    .font(.caption)
                    .foregroundStyle(statusColor)
            }
        }
    }

    private var statusTitle: LocalizedStringKey {
        guard session.isEnabled else { return "settings.accounts.status.disabled" }
        switch session.status {
        case .connecting:
            return "settings.accounts.status.connecting"
        case .ready:
            return "settings.accounts.status.ready"
        case .unreachable:
            return "settings.accounts.status.unreachable"
        case .needsReauthentication:
            return "settings.accounts.status.needsReauthentication"
        }
    }

    private var statusColor: Color {
        guard session.isEnabled else { return .secondary }
        switch session.status {
        case .ready:
            return .green
        case .connecting:
            return .secondary
        case .unreachable, .needsReauthentication:
            return .orange
        }
    }
}

/// Signs in again to an account whose token was revoked; only its servers are reloaded.
struct ReconnectAccountView: View {
    @Environment(SessionManager.self) private var sessionManager
    let account: MediaAccount
    let onDone: () -> Void

    var body: some View {
        Group {
            switch account {
            case .plex:
                SignInView(viewModel: SignInViewModel(onToken: { token in
                    let addition = try await sessionManager.addPlexAccount(token: token)
                    sessionManager.registry.reload(accountID: addition.account.id)
                    onDone()
                }))
            case let .jellyfin(jellyfin):
                JellyfinAuthenticationView(viewModel: JellyfinAuthenticationViewModel(
                    serverURL: jellyfin.connection.baseURL.absoluteString,
                ) { session, connection in
                    try sessionManager.addJellyfinAccount(authenticatedSession: session, connection: connection)
                    sessionManager.registry.reload(accountID: account.id)
                    onDone()
                })
            }
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.actions.cancel", action: onDone)
            }
        }
    }
}
