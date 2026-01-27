import Foundation
import Observation

@MainActor
@Observable
final class SeerrStore {
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored private let baseURLKey = "strimr.seerr.baseURL"
    @ObservationIgnored private let sessionService: SeerrSessionService

    private(set) var baseURLString: String?
    private(set) var user: SeerrUser?
    private(set) var isHydrating = false

    init(userDefaults: UserDefaults = .standard, sessionService: SeerrSessionService = SeerrSessionService()) {
        defaults = userDefaults
        self.sessionService = sessionService
        baseURLString = userDefaults.string(forKey: baseURLKey)
        Task { await hydrateCurrentUser() }
    }

    var isLoggedIn: Bool {
        user != nil
    }

    func setBaseURL(_ urlString: String) {
        baseURLString = urlString
        defaults.set(baseURLString, forKey: baseURLKey)
    }

    func setUser(_ user: SeerrUser?) {
        self.user = user
    }

    func clearUser() {
        user = nil
    }

    private func hydrateCurrentUser() async {
        guard
            let baseURLString,
            let baseURL = URL(string: baseURLString)
        else {
            return
        }

        isHydrating = true
        defer { isHydrating = false }

        do {
            let user = try await sessionService.hydrateCurrentUser(baseURL: baseURL)
            setUser(user)
        } catch {
            clearUser()
        }
    }
}
