import Foundation

/// The app's session, for App Intents and their queries, which SwiftUI does not reach.
@MainActor
enum AppIntentsEnvironment {
    weak static var sessionManager: SessionManager?
    weak static var libraryStore: LibraryStore?

    /// The session once a profile is active. Intents can run while the app is still launching.
    static func readySessionManager(timeout: Duration = .seconds(10)) async -> SessionManager? {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while clock.now < deadline, !Task.isCancelled {
            if let sessionManager, sessionManager.status == .ready {
                return sessionManager
            }
            try? await Task.sleep(for: .milliseconds(250))
        }
        return nil
    }

    /// A server of the active profile, for intents that run without opening the app.
    static func readyServices(for server: ServerIdentity) async -> MediaServices? {
        await readySessionManager()?.registry.services(for: server)
    }
}
