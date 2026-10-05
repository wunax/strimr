import SwiftUI

@main
struct StrimrApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate: AppDelegate

    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var sharePlayCoordinator: SharePlayCoordinator

    init() {
        let favoritesStore = FavoritesStore()
        let settingsManager = SettingsManager()
        let trackSelectionCoordinator = TrackSelectionCoordinator(
            store: TrackSelectionStore(),
            settingsManager: settingsManager,
        )
        let sessionManager = SessionManager(
            settingsManager: settingsManager,
            favoritesStore: favoritesStore,
            trackSelectionCoordinator: trackSelectionCoordinator,
            versionSelectionStore: MediaVersionSelectionStore(),
        )
        let downloadManager = DownloadManager(settingsManager: settingsManager)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        _seerrStore = State(initialValue: SeerrStore())
        _sharePlayCoordinator = State(initialValue: SharePlayCoordinator(
            sessionManager: sessionManager,
        ))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(sessionManager)
                .environment(sessionManager.registry)
                .environment(settingsManager)
                .environment(downloadManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(sharePlayCoordinator)
                .environment(OfflineCoordinator.shared)
                .preferredColorScheme(.dark)
        }
    }
}
