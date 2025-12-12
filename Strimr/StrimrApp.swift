import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let context = PlexAPIContext()
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context))
        _settingsManager = State(initialValue: SettingsManager())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .preferredColorScheme(.dark)
        }
    }
}
