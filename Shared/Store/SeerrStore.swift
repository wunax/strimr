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
    private(set) var quota: SeerrUserQuota?
    private(set) var settings: SeerrSettings?
    private(set) var isHydrating = false

    init(userDefaults: UserDefaults = .standard, sessionService: SeerrSessionService? = nil) {
        defaults = userDefaults
        self.sessionService = sessionService ?? SeerrSessionService()
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

    func setQuota(_ quota: SeerrUserQuota?) {
        self.quota = quota
    }

    func setSettings(_ settings: SeerrSettings?) {
        self.settings = settings
    }

    func clearUser() {
        user = nil
        quota = nil
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
            let settings = try await sessionService.fetchPublicSettings(baseURL: baseURL)
            setSettings(settings)
        } catch {
            setSettings(nil)
        }

        do {
            let user = try await sessionService.hydrateCurrentUser(baseURL: baseURL)
            setUser(user)
            do {
                let quota = try await sessionService.fetchUserQuota(baseURL: baseURL, userId: user.id)
                setQuota(quota)
            } catch {
                setQuota(nil)
            }
        } catch {
            clearUser()
        }
    }
}
