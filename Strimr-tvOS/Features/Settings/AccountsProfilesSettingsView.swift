import SwiftUI

/// "Accounts and servers" in the tvOS settings, built on the settings focus system.
@MainActor
struct TVAccountsSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isAddingAccount = false
    @State private var accountPendingRemoval: MediaAccount?
    @State private var reconnectingAccount: MediaAccount?

    var body: some View {
        SettingsList {
            ForEach(sessionManager.accounts) { account in
                Section {
                    accountContent(account)
                } header: {
                    Text(verbatim: "\(account.displayName) · \(account.provider == .plex ? "Plex" : "Jellyfin")")
                } footer: {
                    if sessionManager.isAccountUnused(account.id) {
                        Text("settings.accounts.unused")
                    }
                }
            }

            Section {
                Button { isAddingAccount = true } label: {
                    Label("settings.accounts.add", systemImage: "plus.circle")
                }
                .foregroundStyle(.primary)
                .settingsFocus("accounts.add", isDefault: sessionManager.accounts.isEmpty)
            }
        }
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
            Button("settings.accounts.remove", role: .destructive) {
                sessionManager.removeAccount(account.id)
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: { account in
            Text("settings.accounts.remove.message \(account.displayName)")
        }
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
            .settingsFocus(
                "accounts.server.\(session.identity.stableKey)",
                isDefault: session.identity == sessionManager.registry.sessions.first?.identity,
            )
            if session.status == .needsReauthentication {
                Button("settings.accounts.reconnect") { reconnectingAccount = account }
                    .settingsFocus("accounts.reconnect.\(session.identity.stableKey)")
            }
        }
        if sessionManager.registry.linkStatuses[account.id] == .needsReauthentication, sessions.isEmpty {
            Button("settings.accounts.reconnect") { reconnectingAccount = account }
                .settingsFocus("accounts.reconnect.\(account.id)")
        }
        Button("settings.accounts.remove", role: .destructive) { accountPendingRemoval = account }
            .settingsFocus("accounts.remove.\(account.id)")
    }

    private func isLinkedToActiveProfile(_ account: MediaAccount) -> Bool {
        guard let profile = sessionManager.activeProfile else { return false }
        return sessionManager.links(for: profile).contains { $0.accountID == account.id }
    }
}

/// Profiles in the tvOS settings; a profile's sheet opens as a modal, outside the settings columns.
@MainActor
struct TVProfilesSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isCreatingProfile = false
    @State private var editedProfile: ProfileSheet?

    private struct ProfileSheet: Identifiable {
        let id: String
        let startsWithNewConnection: Bool
    }

    var body: some View {
        SettingsList {
            Section {
                ForEach(sessionManager.profiles) { profile in
                    Button {
                        editedProfile = ProfileSheet(id: profile.id, startsWithNewConnection: false)
                    } label: {
                        ProfileRow(profile: profile, isActive: profile.id == sessionManager.activeProfile?.id)
                    }
                    .settingsFocus(
                        "profiles.\(profile.id)",
                        isDefault: profile.id == sessionManager.profiles.first?.id,
                    )
                }
            }

            Section {
                Button { isCreatingProfile = true } label: {
                    Label("profiles.create", systemImage: "plus.circle")
                }
                .foregroundStyle(.primary)
                .settingsFocus("profiles.create")
            }

            if sessionManager.profiles.count > 1 {
                Section {
                    Toggle("profiles.askOnLaunch", isOn: Binding(
                        get: { sessionManager.profileStore.asksProfileOnLaunch },
                        set: { sessionManager.setAsksProfileOnLaunch($0) },
                    ))
                    .settingsFocus("profiles.askOnLaunch")
                } footer: {
                    Text("profiles.askOnLaunch.footer")
                }
            }
        }
        .sheet(isPresented: $isCreatingProfile) {
            CreateLocalProfileView(
                onCreate: { profile in
                    isCreatingProfile = false
                    // A new local profile goes straight to "Add a connection": without one it cannot be activated.
                    editedProfile = ProfileSheet(id: profile.id, startsWithNewConnection: true)
                },
                onCancel: { isCreatingProfile = false },
            )
        }
        .sheet(item: $editedProfile) { sheet in
            NavigationStack {
                ProfileDetailView(profileID: sheet.id, startsWithNewConnection: sheet.startsWithNewConnection)
            }
        }
    }
}
