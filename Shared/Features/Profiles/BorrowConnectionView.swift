import SwiftUI

/// Borrows a connection of another profile. A Plex Home user gets its own token through `/switch`; a Jellyfin
/// connection is copied, so both profiles share that Jellyfin user. Jellyfin accounts no profile uses are linked as is.
struct BorrowConnectionView: View {
    @Environment(SessionManager.self) private var sessionManager

    let profileID: String
    let onDone: () -> Void

    @State private var unlockedProfileIDs: Set<String> = []
    @State private var unlockingProfile: LocalProfile?
    @State private var pendingJellyfin: ProfileStore.BorrowableConnection?
    @State private var pendingPlexPIN: ProfileStore.BorrowableConnection?
    @State private var isBorrowing = false
    @State private var errorMessage: String?

    private var profile: StrimrProfile? {
        sessionManager.profileStore.profile(id: profileID, accounts: sessionManager.accounts)
    }

    private var candidates: [ProfileStore.BorrowableConnection] {
        guard let profile else { return [] }
        return sessionManager.profileStore.borrowableConnections(for: profile, accounts: sessionManager.accounts)
    }

    private var sourceProfiles: [StrimrProfile] {
        var seen = Set<String>()
        return candidates.compactMap(\.sourceProfile).filter { seen.insert($0.id).inserted }
    }

    private var unusedAccounts: [ProfileStore.BorrowableConnection] {
        candidates.filter { $0.sourceProfile == nil }
    }

    var body: some View {
        List {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }
            if candidates.isEmpty {
                Text("profiles.borrow.empty")
                    .foregroundStyle(.secondary)
            }
            ForEach(sourceProfiles) { source in
                Section(source.name) {
                    if let local = source.localProfile, local.pin != nil, !unlockedProfileIDs.contains(local.id) {
                        Button("profiles.borrow.unlock") { unlockingProfile = local }
                    } else {
                        ForEach(candidates.filter { $0.sourceProfile?.id == source.id }) { candidate in
                            candidateButton(candidate)
                        }
                    }
                }
            }
            if !unusedAccounts.isEmpty {
                Section("profiles.borrow.unusedAccounts") {
                    ForEach(unusedAccounts) { candidate in
                        candidateButton(candidate)
                    }
                }
            }
        }
        .taskModalTitle("profiles.addConnection.borrow")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("common.actions.cancel", action: onDone)
            }
        }
        .taskPresentation(item: $unlockingProfile, style: .compactModal) { local in
            ProfilePINPrompt(
                title: "auth.profile.pin.title",
                message: String(localized: "auth.profile.pin.prompt \(local.name)"),
                onSubmit: { pin in
                    if local.pin?.verify(pin) == true {
                        unlockedProfileIDs.insert(local.id)
                        errorMessage = nil
                    } else {
                        errorMessage = String(localized: "profiles.pin.wrong")
                    }
                    unlockingProfile = nil
                },
                onCancel: { unlockingProfile = nil },
            )
        }
        .taskPresentation(item: $pendingPlexPIN, style: .compactModal) { candidate in
            ProfilePINPrompt(
                title: "auth.profile.pin.title",
                message: String(localized: "auth.profile.pin.prompt \(userName(candidate))"),
                onSubmit: { pin in
                    pendingPlexPIN = nil
                    Task { await borrowPlex(candidate, pin: pin) }
                },
                onCancel: { pendingPlexPIN = nil },
            )
        }
        .alert(
            "profiles.borrow.confirm",
            isPresented: Binding(get: { pendingJellyfin != nil }, set: {
                if !$0 {
                    pendingJellyfin = nil
                }
            }),
            presenting: pendingJellyfin,
        ) { candidate in
            Button("profiles.borrow.confirm.action") {
                link(candidate)
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: { candidate in
            Text("profiles.borrow.sharedUserWarning \(userName(candidate))")
        }
    }

    private func candidateButton(_ candidate: ProfileStore.BorrowableConnection) -> some View {
        Button {
            borrow(candidate)
        } label: {
            connectionLabel(candidate)
        }
        .disabled(isBorrowing)
    }

    private func connectionLabel(_ candidate: ProfileStore.BorrowableConnection) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(accountTitle(candidate))
            Text(userName(candidate))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func accountTitle(_ candidate: ProfileStore.BorrowableConnection) -> String {
        switch sessionManager.accountStore.account(id: candidate.accountID) {
        case let .plex(account):
            "Plex · \(account.displayName)"
        case let .jellyfin(account):
            account.connection.serverName
        case nil:
            candidate.accountID
        }
    }

    private func userName(_ candidate: ProfileStore.BorrowableConnection) -> String {
        switch candidate.user {
        case let .plexHome(uuid):
            sessionManager.profileStore.plexHomeUsers(accountID: candidate.accountID)
                .first { $0.uuid == uuid }?.displayName ?? uuid
        case .jellyfin:
            sessionManager.accountStore.account(id: candidate.accountID)?.displayName ?? ""
        }
    }

    private func borrow(_ candidate: ProfileStore.BorrowableConnection) {
        errorMessage = nil
        guard candidate.sourceProfile != nil else {
            link(candidate)
            return
        }
        switch candidate.user {
        case .jellyfin:
            // Everything keyed by the Jellyfin user is shared: watch state, downloads, offline journal, cache.
            pendingJellyfin = candidate
        case let .plexHome(uuid):
            let isProtected = sessionManager.profileStore.plexHomeUsers(accountID: candidate.accountID)
                .first { $0.uuid == uuid }?.protected ?? false
            if isProtected {
                pendingPlexPIN = candidate
            } else {
                Task { await borrowPlex(candidate, pin: nil) }
            }
        }
    }

    private func borrowPlex(_ candidate: ProfileStore.BorrowableConnection, pin: String?) async {
        guard case let .plexHome(uuid) = candidate.user else { return }
        isBorrowing = true
        defer { isBorrowing = false }
        do {
            _ = try await sessionManager.switchPlexHomeUser(accountID: candidate.accountID, userUUID: uuid, pin: pin)
            link(candidate)
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            if !error.isTransportFailure, !error.isAuthenticationFailure {
                ErrorReporter.capture(error)
            }
            errorMessage = String(localized: "auth.profile.error.switchFailed")
        }
    }

    private func link(_ candidate: ProfileStore.BorrowableConnection) {
        sessionManager.addLink(ProfileLink(profileID: profileID, accountID: candidate.accountID, user: candidate.user))
        onDone()
    }
}
