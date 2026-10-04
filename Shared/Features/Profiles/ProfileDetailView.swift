import SwiftUI

/// A profile's sheet: name and PIN of a local profile, its connections, the Plex account of its watchlist.
struct ProfileDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    let profileID: String
    var startsWithNewConnection = false

    @State private var name = ""
    @State private var newPIN = ""
    @State private var isChoosingConnection = false
    @State private var isAddingNewConnection = false
    @State private var isBorrowingConnection = false
    @State private var isConfirmingDeletion = false
    @State private var hasPresentedInitialConnection = false

    private var profile: StrimrProfile? {
        sessionManager.profileStore.profile(id: profileID, accounts: sessionManager.accounts)
    }

    var body: some View {
        Group {
            if let profile {
                form(for: profile)
            } else {
                ContentUnavailableView("profiles.missing", systemImage: "person.crop.circle.badge.questionmark")
            }
        }
        .navigationTitle(profile?.name ?? "")
        .onAppear {
            name = profile?.localProfile?.name ?? ""
            guard startsWithNewConnection, !hasPresentedInitialConnection else { return }
            hasPresentedInitialConnection = true
            isChoosingConnection = true
        }
        .confirmationDialog("profiles.addConnection", isPresented: $isChoosingConnection) {
            Button("profiles.addConnection.new") { isAddingNewConnection = true }
            if canBorrow {
                Button("profiles.addConnection.borrow") { isBorrowingConnection = true }
            }
            Button("common.actions.cancel", role: .cancel) {}
        }
        .sheet(isPresented: $isAddingNewConnection) {
            AccountSetupView(purpose: .profile(profileID), sessionManager: sessionManager) {
                isAddingNewConnection = false
            }
        }
        .sheet(isPresented: $isBorrowingConnection) {
            NavigationStack {
                BorrowConnectionView(profileID: profileID) { isBorrowingConnection = false }
            }
        }
        .alert("profiles.delete.title", isPresented: $isConfirmingDeletion) {
            Button("profiles.delete", role: .destructive) {
                sessionManager.deleteLocalProfile(profileID)
                dismiss()
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("profiles.delete.message")
        }
    }

    private var canBorrow: Bool {
        sessionManager.canManageAccounts && !(profile?.isRestricted ?? true)
    }

    private func form(for profile: StrimrProfile) -> some View {
        Form {
            if let local = profile.localProfile {
                Section("profiles.name") {
                    TextField("profiles.name", text: $name)
                        .onSubmit { rename(local) }
                        .onDisappear { rename(local) }
                }
                Section("profiles.pin") {
                    SecureField(local.pin == nil ? "profiles.pin.set" : "profiles.pin.change", text: $newPIN)
                    #if os(iOS)
                        .keyboardType(.numberPad)
                    #endif
                    Button("profiles.pin.save") { savePIN(local) }
                        .disabled(newPIN.filter(\.isNumber).count != 4)
                    if local.pin != nil {
                        Button("profiles.pin.remove", role: .destructive) {
                            var updated = local
                            updated.pin = nil
                            sessionManager.profileStore.updateLocalProfile(updated)
                        }
                    }
                }
            }

            Section {
                ForEach(sessionManager.links(for: profile), id: \.self) { link in
                    connectionRow(link, profile: profile)
                }
                Button("profiles.addConnection") { isChoosingConnection = true }
            } header: {
                Text("profiles.connections")
            } footer: {
                if !sessionManager.profileStore.hasLinks(profile) {
                    Text("profiles.connections.required")
                }
            }

            let plexAccountIDs = plexAccountIDs(of: profile)
            if plexAccountIDs.count > 1 {
                Section {
                    Picker("profiles.watchlistAccount", selection: Binding(
                        get: {
                            sessionManager.profileStore.watchlistAccountID(
                                for: profile,
                                accounts: sessionManager.accounts,
                            ) ?? ""
                        },
                        set: { sessionManager.profileStore.setWatchlistAccount($0, profileID: profile.id) },
                    )) {
                        ForEach(plexAccountIDs, id: \.self) { accountID in
                            Text(sessionManager.accountStore.account(id: accountID)?.displayName ?? accountID)
                                .tag(accountID)
                        }
                    }
                }
            }

            if profile.isLocal {
                Section {
                    Button("profiles.delete", role: .destructive) { isConfirmingDeletion = true }
                }
            }
        }
    }

    private func connectionRow(_ link: ProfileLink, profile: StrimrProfile) -> some View {
        let isImplicit = profile.plexHomeProfile?.implicitLink == link
        return HStack {
            VStack(alignment: .leading, spacing: 2) {
                Text(title(of: link))
                Text(subtitle(of: link))
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if !isImplicit {
                Button("profiles.connection.remove", role: .destructive) {
                    sessionManager.removeLink(profileID: profile.id, accountID: link.accountID)
                }
                .buttonStyle(.borderless)
            }
        }
    }

    private func title(of link: ProfileLink) -> String {
        switch sessionManager.accountStore.account(id: link.accountID) {
        case let .plex(account):
            "Plex · \(account.displayName)"
        case let .jellyfin(account):
            account.connection.serverName
        case nil:
            link.accountID
        }
    }

    private func subtitle(of link: ProfileLink) -> String {
        switch link.user {
        case let .plexHome(uuid):
            sessionManager.profileStore.plexHomeUsers(accountID: link.accountID)
                .first { $0.uuid == uuid }?.displayName ?? uuid
        case .jellyfin:
            sessionManager.accountStore.account(id: link.accountID)?.displayName ?? ""
        }
    }

    private func plexAccountIDs(of profile: StrimrProfile) -> [String] {
        sessionManager.links(for: profile).map(\.accountID).filter {
            sessionManager.accountStore.account(id: $0)?.provider == .plex
        }
    }

    private func rename(_ profile: LocalProfile) {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, trimmed != profile.name else { return }
        var updated = profile
        updated.name = trimmed
        sessionManager.profileStore.updateLocalProfile(updated)
    }

    private func savePIN(_ profile: LocalProfile) {
        let digits = String(newPIN.filter(\.isNumber).prefix(4))
        guard digits.count == 4 else { return }
        var updated = profile
        updated.pin = LocalProfilePIN(pin: digits)
        sessionManager.profileStore.updateLocalProfile(updated)
        newPIN = ""
    }
}
