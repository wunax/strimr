import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    init() {
        let context = PlexAPIContext()
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context))
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: LibraryStore(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .preferredColorScheme(.dark)
        }
    }
}
