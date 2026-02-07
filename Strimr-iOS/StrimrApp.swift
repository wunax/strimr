import SwiftUI

@main
struct StrimrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var watchTogetherViewModel: WatchTogetherViewModel

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: store)
        let settingsManager = SettingsManager()
        let downloadManager = DownloadManager(settingsManager: settingsManager)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: store)
        _seerrStore = State(initialValue: SeerrStore())
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: sessionManager,
            context: context,
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(downloadManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(watchTogetherViewModel)
                .preferredColorScheme(.dark)
        }
    }
}
