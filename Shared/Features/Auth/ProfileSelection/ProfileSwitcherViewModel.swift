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
        userRepository = UserRepository(context: context)
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
        } catch {
            users = []
            errorMessage = String(localized: "auth.profile.error.loadFailed")
            ErrorReporter.capture(error)
        }
    }

    func switchToUser(_ user: PlexHomeUser, pin: String?) async {
        guard switchingUserUUID == nil else { return }

        if requiresPin(for: user), pin?.isEmpty ?? true {
            errorMessage = String(localized: "auth.profile.error.pinRequired")
            return
        }

        switchingUserUUID = user.uuid
        errorMessage = nil
        defer { switchingUserUUID = nil }

        do {
            let switchedUser = try await userRepository.switchUser(uuid: user.uuid, pin: pin)
            try await sessionManager.switchProfile(to: switchedUser)
        } catch {
            errorMessage = String(localized: "auth.profile.error.switchFailed")
            ErrorReporter.capture(error)
        }
    }

    private func requiresPin(for user: PlexHomeUser) -> Bool {
        user.protected ?? false
    }
}
