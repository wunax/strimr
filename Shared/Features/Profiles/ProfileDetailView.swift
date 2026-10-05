import SwiftUI

/// A profile's sheet: name and PIN of a local profile, its connections, the Plex account of its watchlist.
struct ProfileDetailView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss

    let profileID: String
    var startsWithNewConnection = false

    @State private var name = ""
    @State private var isEditingPIN = false
    @State private var isChoosingConnection = false
    @State private var isAddingNewConnection = false
    @State private var isBorrowingConnection = false
    @State private var isConfirmingDeletion = false
    @State private var hasPresentedInitialConnection = false
    @State private var linkPendingRemoval: ProfileLink?

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
        .taskModalTitle(verbatim: profile?.name ?? "")
        .onAppear {
            name = profile?.localProfile?.name ?? ""
            guard startsWithNewConnection, !hasPresentedInitialConnection else { return }
            hasPresentedInitialConnection = true
            isChoosingConnection = true
        }
        .confirmationDialog("profiles.addConnection", isPresented: $isChoosingConnection) {
            Button("profiles.addConnection.new") { isAddingNewConnection = true }
            Button("profiles.addConnection.borrow") { isBorrowingConnection = true }
            Button("common.actions.cancel", role: .cancel) {}
        }
        .taskPresentation(isPresented: $isAddingNewConnection, style: .fullScreen) {
            AccountSetupView(purpose: .profile(profileID), sessionManager: sessionManager) {
                isAddingNewConnection = false
            }
        }
        .taskPresentation(isPresented: $isBorrowingConnection, style: .compactModal) {
            TaskModalNavigationView {
                BorrowConnectionView(profileID: profileID) { isBorrowingConnection = false }
            }
        }
        .taskPresentation(isPresented: $isEditingPIN) {
            ProfilePINSettingsView(profileID: profileID)
        }
        .confirmationDialog(
            linkPendingRemoval.map(title(of:)) ?? "",
            isPresented: Binding(get: { linkPendingRemoval != nil }, set: {
                if !$0 {
                    linkPendingRemoval = nil
                }
            }),
            titleVisibility: .visible,
            presenting: linkPendingRemoval,
        ) { link in
            Button("profiles.connection.remove", role: .destructive) {
                sessionManager.removeLink(profileID: profileID, accountID: link.accountID)
            }
            Button("common.actions.cancel", role: .cancel) {}
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

    @ViewBuilder
    private func form(for profile: StrimrProfile) -> some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 32) {
                if let local = profile.localProfile {
                    TVProfileNameField(text: $name)
                        .onSubmit { rename(local) }
                        .onDisappear { rename(local) }
                }
                rows(for: profile)
            }
        #else
            rows(for: profile)
        #endif
    }

    private func rows(for profile: StrimrProfile) -> some View {
        Form {
            if let local = profile.localProfile {
                #if !os(tvOS)
                    Section("profiles.name") {
                        TextField("profiles.name", text: $name)
                            .onSubmit { rename(local) }
                            .onDisappear { rename(local) }
                    }
                #endif
                Section {
                    Button { isEditingPIN = true } label: {
                        HStack {
                            Text("profiles.pin")
                            Spacer()
                            Text(local.pin == nil ? "profiles.pin.disabled" : "profiles.pin.enabled")
                                .foregroundStyle(.secondary)
                            Image(systemName: "chevron.right")
                                .font(.footnote.weight(.semibold))
                                .foregroundStyle(.tertiary)
                        }
                    }
                    .foregroundStyle(.primary)
                }
            }

            Section {
                ForEach(sessionManager.links(for: profile), id: \.self) { link in
                    connectionRow(link, profile: profile)
                }
                Button { isChoosingConnection = true } label: {
                    Label("profiles.addConnection", systemImage: "plus.circle")
                }
                .foregroundStyle(.primary)
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

            if sessionManager.canDeleteProfile(profile) {
                Section {
                    Button("profiles.delete", role: .destructive) { isConfirmingDeletion = true }
                }
            }
        }
    }

    @ViewBuilder
    private func connectionRow(_ link: ProfileLink, profile: StrimrProfile) -> some View {
        let isImplicit = profile.plexHomeProfile?.implicitLink == link
        #if os(tvOS)
            // A trailing button cannot take focus inside a tvOS row: the row itself offers the removal.
            Button { linkPendingRemoval = link } label: {
                connectionLabel(link)
            }
            .disabled(isImplicit)
        #else
            HStack {
                connectionLabel(link)
                Spacer()
                if !isImplicit {
                    Button("profiles.connection.remove", role: .destructive) {
                        sessionManager.removeLink(profileID: profile.id, accountID: link.accountID)
                    }
                    .buttonStyle(.borderless)
                }
            }
        #endif
    }

    private func connectionLabel(_ link: ProfileLink) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(of: link))
            Text(subtitle(of: link))
                .font(.caption)
                .foregroundStyle(.secondary)
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
}

/// Edits a local profile's PIN only when explicitly opened from its settings.
struct ProfilePINSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    let profileID: String

    @State private var newPIN = ""
    @FocusState private var isPINFocused: Bool

    private var profile: LocalProfile? {
        sessionManager.profileStore.profile(id: profileID, accounts: sessionManager.accounts)?.localProfile
    }

    private var hasPIN: Bool {
        profile?.pin != nil
    }

    private var digits: String {
        newPIN.filter(\.isNumber)
    }

    private var canSave: Bool {
        profile != nil && digits.count == 4
    }

    private var actionTitle: LocalizedStringKey {
        hasPIN ? "profiles.pin.edit" : "profiles.pin.define"
    }

    var body: some View {
        #if os(tvOS)
            TVPINPadView(title: actionTitle, onComplete: save, onCancel: { dismiss() }) {
                if hasPIN {
                    removeButton
                        .buttonStyle(.bordered)
                }
            }
        #else
            NavigationStack {
                Form {
                    Section {
                        pinField
                        saveButton
                    }
                    if hasPIN {
                        Section {
                            removeButton
                        }
                    }
                }
                .navigationTitle(actionTitle)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.cancel") { dismiss() }
                    }
                }
            }
        #endif
    }

    private var pinField: some View {
        SecureField("profiles.pin.set", text: $newPIN)
            .focused($isPINFocused)
        #if os(iOS)
            .keyboardType(.numberPad)
        #endif
            .onSubmit {
                if canSave {
                    savePIN()
                }
            }
    }

    private var saveButton: some View {
        Button(actionTitle, action: savePIN)
            .disabled(!canSave)
    }

    private var removeButton: some View {
        Button("profiles.pin.remove", role: .destructive) {
            guard var updated = profile else { return }
            updated.pin = nil
            sessionManager.profileStore.updateLocalProfile(updated)
            dismiss()
        }
    }

    private func savePIN() {
        guard canSave else { return }
        save(digits)
    }

    private func save(_ pin: String) {
        guard var updated = profile else { return }
        updated.pin = LocalProfilePIN(pin: pin)
        sessionManager.profileStore.updateLocalProfile(updated)
        dismiss()
    }
}
