import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context, libraryStore: store))
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
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
