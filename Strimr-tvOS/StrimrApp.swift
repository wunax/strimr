import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mediaFocusModel: MediaFocusModel
    @State private var seerrStore: SeerrStore
    @State private var seerrFocusModel: SeerrFocusModel

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: SessionManager(context: context, libraryStore: store))
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
        _mediaFocusModel = State(initialValue: MediaFocusModel())
        _seerrStore = State(initialValue: SeerrStore())
        _seerrFocusModel = State(initialValue: SeerrFocusModel())
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(mediaFocusModel)
                .environment(seerrStore)
                .environment(seerrFocusModel)
                .preferredColorScheme(.dark)
        }
    }
}
