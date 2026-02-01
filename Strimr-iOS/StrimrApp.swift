import SwiftUI

@main
struct StrimrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context, libraryStore: store))
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
        _seerrStore = State(initialValue: SeerrStore())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .preferredColorScheme(.dark)
        }
    }
}
