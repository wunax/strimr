import SwiftUI

@main
struct StrimrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var plexApiContext: PlexAPIContext
    @State private var jellyfinAPIContext: JellyfinAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var sharePlayCoordinator: SharePlayCoordinator

    init() {
        let context = PlexAPIContext()
        let jellyfinContext = JellyfinAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(
            context: context,
            jellyfinContext: jellyfinContext,
            libraryStore: store,
        )
        let settingsManager = SettingsManager()
        let downloadManager = DownloadManager(settingsManager: settingsManager)
        _plexApiContext = State(initialValue: context)
        _jellyfinAPIContext = State(initialValue: jellyfinContext)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: store)
        _seerrStore = State(initialValue: SeerrStore())
        _sharePlayCoordinator = State(initialValue: SharePlayCoordinator(
            sessionManager: sessionManager,
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(jellyfinAPIContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(downloadManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(sharePlayCoordinator)
                .preferredColorScheme(.dark)
        }
    }
}
