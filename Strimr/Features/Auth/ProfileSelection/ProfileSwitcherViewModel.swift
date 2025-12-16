import Foundation
import Observation

@MainActor
@Observable
final class ProfileSwitcherViewModel {
    var users: [PlexHomeUser] = []
    var isLoading = false
    var errorMessage: String?
    var switchingUserUUID: String?

    @ObservationIgnored private let userRepository: UserRepository
    @ObservationIgnored private let sessionManager: SessionManager

    init(context: PlexAPIContext, sessionManager: SessionManager) {
        self.userRepository = UserRepository(context: context)
        self.sessionManager = sessionManager
    }

    var activeUserUUID: String? {
        sessionManager.user?.uuid
    }

    func loadUsers() async {
        guard !isLoading else { return }

        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let home = try await userRepository.getHomeUsers()
            users = home.users

            if sessionManager.status == .needsProfileSelection,
               home.users.count == 1,
               let onlyUser = home.users.first,
               requiresPin(for: onlyUser) == false
            {
                await switchToUser(onlyUser, pin: nil)
            }
        } catch {
            users = []
            errorMessage = "Unable to load profiles. Please try again."
        }
    }

    func switchToUser(_ user: PlexHomeUser, pin: String?) async {
        guard switchingUserUUID == nil else { return }

        if requiresPin(for: user) && (pin?.isEmpty ?? true) {
            errorMessage = "Enter the PIN for this profile."
            return
        }

        switchingUserUUID = user.uuid
        errorMessage = nil
        defer { switchingUserUUID = nil }

        do {
            let switchedUser = try await userRepository.switchUser(uuid: user.uuid, pin: pin)
            await sessionManager.switchProfile(to: switchedUser)
        } catch {
            errorMessage = "Unable to switch profile. Check the PIN and try again."
        }
    }

    private func requiresPin(for user: PlexHomeUser) -> Bool {
        user.protected ?? false
    }
}
