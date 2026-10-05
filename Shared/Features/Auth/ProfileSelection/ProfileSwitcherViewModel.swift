import Foundation
import Observation

/// One entry of the profile picker.
struct ProfileChoice: Identifiable, Hashable {
    let id: String
    let name: String
    let detail: String?
    let avatarURL: URL?
    let requiresPIN: Bool
    let isActive: Bool
    let isLocal: Bool

    var initials: String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

/// Picks a Strimr profile to activate, or a Plex Home user of an account while adding a connection.
@MainActor
@Observable
final class ProfileSwitcherViewModel {
    enum Mode {
        case activateProfile
        /// While adding a Plex account: the chosen Home user and its token are handed back.
        case chooseHomeUser(accountID: String, onChoose: (String, String) async -> Void)
    }

    var choices: [ProfileChoice] = []
    var isLoading = false
    var errorMessage: String?
    var switchingID: String?
    /// A local profile without connections was picked: its sheet opens on "Add a connection".
    var profileNeedingConnection: LocalProfile?

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored let mode: Mode

    init(sessionManager: SessionManager, mode: Mode = .activateProfile) {
        self.sessionManager = sessionManager
        self.mode = mode
    }

    var canManageProfiles: Bool {
        if case .activateProfile = mode {
            return sessionManager.canManageAccounts
        }
        return false
    }

    var canCancel: Bool {
        if case .activateProfile = mode {
            return sessionManager.activeProfile != nil
        }
        return false
    }

    func load() async {
        guard !isLoading else { return }
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }
        refreshChoices()
        switch mode {
        case .activateProfile:
            for account in sessionManager.accountStore.plexAccounts {
                await sessionManager.refreshPlexHomeUsers(accountID: MediaAccount.plexID(account.id))
            }
        case let .chooseHomeUser(accountID, _):
            await sessionManager.refreshPlexHomeUsers(accountID: accountID)
        }
        refreshChoices()
    }

    func refreshChoices() {
        let activeID = sessionManager.activeProfile?.id
        switch mode {
        case .activateProfile:
            choices = sessionManager.profiles.map { profile in
                switch profile {
                case let .local(local):
                    ProfileChoice(
                        id: local.id,
                        name: local.name,
                        detail: nil,
                        avatarURL: nil,
                        requiresPIN: local.pin != nil,
                        isActive: local.id == activeID,
                        isLocal: true,
                    )
                case let .plexHome(home):
                    Self.choice(for: home.user, id: home.id, isActive: home.id == activeID)
                }
            }
        case let .chooseHomeUser(accountID, _):
            choices = sessionManager.profileStore.plexHomeUsers(accountID: accountID).map {
                Self.choice(for: $0, id: $0.uuid, isActive: false)
            }
        }
    }

    private static func choice(for user: PlexHomeUser, id: String, isActive: Bool) -> ProfileChoice {
        ProfileChoice(
            id: id,
            name: user.displayName,
            detail: user.username ?? user.email,
            avatarURL: user.thumb,
            requiresPIN: user.protected ?? false,
            isActive: isActive,
            isLocal: false,
        )
    }

    /// Plex Home PINs are checked by Plex and asked on every activation; local PINs are checked against their hash.
    func select(_ choice: ProfileChoice, pin: String?) async {
        guard switchingID == nil else { return }
        if choice.requiresPIN, pin?.isEmpty ?? true {
            errorMessage = String(localized: "auth.profile.error.pinRequired")
            return
        }
        switchingID = choice.id
        errorMessage = nil
        defer { switchingID = nil }

        switch mode {
        case .activateProfile:
            await activate(choice, pin: pin)
        case let .chooseHomeUser(accountID, onChoose):
            do {
                let token = try await sessionManager.switchPlexHomeUser(
                    accountID: accountID,
                    userUUID: choice.id,
                    pin: pin,
                )
                await onChoose(choice.id, token)
            } catch {
                handleSwitchError(error)
            }
        }
    }

    private func activate(_ choice: ProfileChoice, pin: String?) async {
        guard let profile = sessionManager.profiles.first(where: { $0.id == choice.id }) else { return }
        switch profile {
        case let .local(local):
            if let storedPIN = local.pin, !storedPIN.verify(pin ?? "") {
                errorMessage = String(localized: "profiles.pin.wrong")
                return
            }
            guard sessionManager.profileStore.hasLinks(profile) else {
                profileNeedingConnection = local
                return
            }
            await sessionManager.activate(profile)
        case let .plexHome(home):
            do {
                let token = try await sessionManager.switchPlexHomeUser(
                    accountID: home.accountID,
                    userUUID: home.user.uuid,
                    pin: pin,
                )
                await sessionManager.activate(profile, plexHomeToken: token)
            } catch {
                handleSwitchError(error)
            }
        }
    }

    private func handleSwitchError(_ error: Error) {
        guard !Task.isCancelled, !error.isCancellation else { return }
        if case let PlexAPIError.requestFailed(statusCode) = error, statusCode == 401 || statusCode == 403 {
            errorMessage = String(localized: "profiles.pin.wrong")
            return
        }
        errorMessage = String(localized: "auth.profile.error.switchFailed")
        if !error.isTransportFailure {
            ErrorReporter.capture(error)
        }
    }

    func cancel() {
        sessionManager.cancelProfileSelection()
    }
}
