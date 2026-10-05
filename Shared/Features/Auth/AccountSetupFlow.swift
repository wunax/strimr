import Foundation
import Observation

/// Adding a Plex account or a Jellyfin server, at first launch, from the settings or from a profile.
@MainActor
@Observable
final class AccountSetupFlow {
    enum Purpose: Equatable {
        /// First launch: the chosen Plex Home user or the Jellyfin profile becomes the active profile.
        case firstLaunch
        /// From the settings: a Jellyfin server joins the active profile, a Plex account brings new Home profiles.
        case settings
        /// From a profile: the new connection is linked to that profile.
        case profile(String)
    }

    enum Step: Hashable {
        case plexSignIn
        case jellyfin
        case plexHomeUser(accountID: String)
        case plexServers(accountID: String, userUUID: String)
        case addAnotherAccount
    }

    var path: [Step] = []
    private(set) var isFinished = false

    let purpose: Purpose
    @ObservationIgnored let sessionManager: SessionManager
    /// Accounts added for a profile's new connection; removed again if the user backs out before choosing a user.
    @ObservationIgnored private var temporaryAccountIDs: Set<String> = []
    /// After the first account, the first launch continues like the settings.
    private var isAddingAnotherAccount = false

    init(purpose: Purpose, sessionManager: SessionManager) {
        self.purpose = purpose
        self.sessionManager = sessionManager
    }

    private var effectivePurpose: Purpose {
        purpose == .firstLaunch && isAddingAnotherAccount ? .settings : purpose
    }

    // MARK: - Steps

    func choose(_ provider: MediaProvider) {
        path.append(provider == .plex ? .plexSignIn : .jellyfin)
    }

    func plexSignedIn(token: String) async throws {
        let addition = try await sessionManager.addPlexAccount(token: token)
        let accountID = addition.account.id
        switch effectivePurpose {
        case .firstLaunch:
            if addition.homeUsers.count > 1 {
                path.append(.plexHomeUser(accountID: accountID))
            } else {
                await plexHomeUserChosen(accountID: accountID, userUUID: addition.ownerUUID, token: token)
            }
        case .settings:
            completeSettingsAddition()
        case .profile:
            if !addition.wasAlreadyAdded {
                temporaryAccountIDs.insert(accountID)
            }
            path.append(.plexHomeUser(accountID: accountID))
        }
    }

    func plexHomeUserChosen(accountID: String, userUUID: String, token: String) async {
        temporaryAccountIDs.remove(accountID)
        let profileID = PlexHomeProfile.id(userUUID: userUUID)
        switch effectivePurpose {
        case .firstLaunch:
            sessionManager.accountStore.setHomeToken(token, accountID: accountID, userUUID: userUUID)
            sessionManager.profileStore.setActiveProfile(profileID)
            path.append(.plexServers(accountID: accountID, userUUID: userUUID))
        case .settings:
            completeSettingsAddition()
        case let .profile(targetProfileID):
            sessionManager.accountStore.setHomeToken(token, accountID: accountID, userUUID: userUUID)
            sessionManager.addLink(ProfileLink(
                profileID: targetProfileID,
                accountID: accountID,
                user: .plexHome(uuid: userUUID),
            ))
            isFinished = true
        }
    }

    /// Servers of the first account; unchecked ones stay disabled for the active profile only.
    func plexServersChosen(accountID: String, userUUID: String, disabledServerIDs: Set<String>) {
        sessionManager.profileStore.setServerSelection(
            .allExcept(disabledServerIDs),
            profileID: PlexHomeProfile.id(userUUID: userUUID),
            accountID: accountID,
        )
        path.append(.addAnotherAccount)
    }

    func jellyfinSignedIn(session: JellyfinAuthenticatedSession, connection: JellyfinConnection) throws {
        let target: String? = if case let .profile(profileID) = effectivePurpose {
            profileID
        } else {
            nil
        }
        let account = try sessionManager.addJellyfinAccount(
            authenticatedSession: session,
            connection: connection,
            linkingTo: target,
        )
        switch effectivePurpose {
        case .firstLaunch:
            if let profile = sessionManager.profileStore.state.links.first(where: { $0.accountID == account.id }) {
                sessionManager.profileStore.setActiveProfile(profile.profileID)
            }
            path.append(.addAnotherAccount)
        case .settings:
            completeSettingsAddition()
        case .profile:
            isFinished = true
        }
    }

    /// Optional step of the first launch: adding a Plex account or a Jellyfin server, like from the settings.
    func addAnotherAccount() {
        isAddingAnotherAccount = true
        path.removeAll()
    }

    /// The first launch can be completed from the provider choice once a first account exists.
    var canFinishFromProviderChoice: Bool {
        purpose == .firstLaunch && isAddingAnotherAccount
    }

    func finish() async {
        guard purpose == .firstLaunch else {
            isFinished = true
            return
        }
        await sessionManager.finishFirstLaunch()
    }

    /// Leaving a profile's new connection before choosing the Home user removes the account added for it.
    func cancel() {
        for accountID in temporaryAccountIDs {
            sessionManager.removeAccount(accountID)
        }
        temporaryAccountIDs = []
        isFinished = true
    }

    private func completeSettingsAddition() {
        if purpose == .firstLaunch {
            path = [.addAnotherAccount]
        } else {
            isFinished = true
        }
    }
}
