import Observation
import SwiftUI

/// One entry of the profile picker.
struct ProfileChoice: Identifiable, Hashable {
    let id: String
    let avatarProfileID: String
    let name: String
    let detail: String?
    let avatarURL: URL?
    let requiresPIN: Bool
    let isActive: Bool
    let isLocal: Bool
    let tint: Color

    var initials: String {
        Self.initials(for: name)
    }

    static func initials(for name: String) -> String {
        let words = name.split(separator: " ").prefix(2)
        let letters = words.compactMap(\.first).map(String.init).joined()
        return letters.isEmpty ? "?" : letters.uppercased()
    }
}

extension ProfileChoice {
    init(profile: StrimrProfile, isActive: Bool) {
        switch profile {
        case let .local(local):
            self.init(
                id: local.id,
                avatarProfileID: local.id,
                name: local.name,
                detail: nil,
                avatarURL: nil,
                requiresPIN: local.pin != nil,
                isActive: isActive,
                isLocal: true,
                tint: ProfileTint.color(for: local.id),
            )
        case let .plexHome(home):
            self.init(homeUser: home.user, id: home.id, isActive: isActive)
        }
    }

    /// While adding an account, selection uses the UUID; avatar ownership and tint use the canonical profile ID.
    init(homeUser user: PlexHomeUser, id: String, isActive: Bool) {
        self.init(
            id: id,
            avatarProfileID: PlexHomeProfile.id(userUUID: user.uuid),
            name: user.displayName,
            detail: user.username ?? user.email,
            avatarURL: user.thumb,
            requiresPIN: user.protected ?? false,
            isActive: isActive,
            isLocal: false,
            tint: ProfileTint.color(for: PlexHomeProfile.id(userUUID: user.uuid)),
        )
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
    /// Bumped on every rejected PIN so the entry can shake and clear.
    var rejectedPINCount = 0
    /// The profile being entered: its entrance plays before the session switches to it.
    var enteringID: String?
    /// Focused, hovered or last touched profile; it tints the picker.
    var highlightedID: String?
    /// PIN-protected profile whose PIN is being typed in the picker.
    var pinChoice: ProfileChoice?
    var pin = ""

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

    var tint: Color? {
        let highlighted = choices.first { $0.id == highlightedID }
        let fallback = choices.first(where: \.isActive) ?? choices.first
        return (pinChoice ?? highlighted ?? fallback)?.tint
    }

    var enteringChoice: ProfileChoice? {
        choices.first { $0.id == enteringID }
    }

    func choose(_ choice: ProfileChoice) {
        highlightedID = choice.id
        guard choice.requiresPIN else {
            Task { await select(choice, pin: nil) }
            return
        }
        errorMessage = nil
        pin = ""
        pinChoice = choice
    }

    func appendPINDigit(_ digit: String) {
        guard let pinChoice, switchingID == nil, pin.count < 4 else { return }
        pin.append(digit)
        guard pin.count == 4 else { return }
        let entered = pin
        Task {
            await select(pinChoice, pin: entered)
            pin = ""
        }
    }

    func deletePINDigit() {
        guard switchingID == nil, !pin.isEmpty else { return }
        pin.removeLast()
    }

    func cancelPIN() {
        guard switchingID == nil else { return }
        pinChoice = nil
        pin = ""
        errorMessage = nil
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
            choices = sessionManager.profiles.map { ProfileChoice(profile: $0, isActive: $0.id == activeID) }
        case let .chooseHomeUser(accountID, _):
            choices = sessionManager.profileStore.plexHomeUsers(accountID: accountID).map {
                ProfileChoice(homeUser: $0, id: $0.uuid, isActive: false)
            }
        }
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
        defer {
            switchingID = nil
            enteringID = nil
        }

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
                rejectPIN()
                return
            }
            guard sessionManager.profileStore.hasLinks(profile) else {
                pinChoice = nil
                profileNeedingConnection = local
                return
            }
            await playEntrance(of: choice)
            await sessionManager.activate(profile)
        case let .plexHome(home):
            do {
                let token = try await sessionManager.switchPlexHomeUser(
                    accountID: home.accountID,
                    userUUID: home.user.uuid,
                    pin: pin,
                )
                await playEntrance(of: choice)
                await sessionManager.activate(profile, plexHomeToken: token)
            } catch {
                handleSwitchError(error)
            }
        }
    }

    private func handleSwitchError(_ error: Error) {
        guard !Task.isCancelled, !error.isCancellation else { return }
        if case let PlexAPIError.requestFailed(statusCode) = error, statusCode == 401 || statusCode == 403 {
            rejectPIN()
            return
        }
        errorMessage = String(localized: "auth.profile.error.switchFailed")
        if !error.isTransportFailure {
            ErrorReporter.capture(error)
        }
    }

    private func rejectPIN() {
        errorMessage = String(localized: "profiles.pin.wrong")
        rejectedPINCount += 1
    }

    private func playEntrance(of choice: ProfileChoice) async {
        enteringID = choice.id
        try? await Task.sleep(for: .milliseconds(500))
    }

    func cancel() {
        sessionManager.cancelProfileSelection()
    }
}
