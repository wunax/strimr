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
    @State private var externalPlaybackCallbackRouter = ExternalPlaybackCallbackRouter()

    init() {
        let favoritesStore = FavoritesStore()
        #if DEBUG
            let demoStores = DemoStores.makeIfEnabled()
            let settingsManager = demoStores.map { SettingsManager(userDefaults: $0.defaults) } ?? SettingsManager()
        #else
            let settingsManager = SettingsManager()
        #endif
        let trackSelectionCoordinator = TrackSelectionCoordinator(
            store: TrackSelectionStore(),
            settingsManager: settingsManager,
        )
        #if DEBUG
            let sessionManager = SessionManager(
                settingsManager: settingsManager,
                favoritesStore: favoritesStore,
                trackSelectionCoordinator: trackSelectionCoordinator,
                versionSelectionStore: MediaVersionSelectionStore(),
                accountStore: demoStores?.accountStore,
                profileStore: demoStores?.profileStore,
            )
        #else
            let sessionManager = SessionManager(
                settingsManager: settingsManager,
                favoritesStore: favoritesStore,
                trackSelectionCoordinator: trackSelectionCoordinator,
                versionSelectionStore: MediaVersionSelectionStore(),
            )
        #endif
        let downloadManager = DownloadManager(settingsManager: settingsManager)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: downloadManager)
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        #if DEBUG
            _seerrStore = State(initialValue: SeerrStore(userDefaults: demoStores?.defaults ?? .standard))
        #else
            _seerrStore = State(initialValue: SeerrStore())
        #endif
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
                .environment(externalPlaybackCallbackRouter)
                .preferredColorScheme(.dark)
                .onOpenURL { externalPlaybackCallbackRouter.receive($0) }
        }
    }
}
