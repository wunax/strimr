import SwiftUI

@main
struct StrimrApp: App {
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var appModel: AppModel
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

        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: DownloadManager(settingsManager: settingsManager))
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        #if DEBUG
            _seerrStore = State(initialValue: SeerrStore(userDefaults: demoStores?.defaults ?? .standard))
        #else
            _seerrStore = State(initialValue: SeerrStore())
        #endif
        _appModel = State(initialValue: AppModel(settingsManager: settingsManager))
        _sharePlayCoordinator = State(initialValue: SharePlayCoordinator(
            sessionManager: sessionManager,
        ))
    }

    var body: some Scene {
        WindowGroup {
            configured(ContentView())
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1440, height: 900)

        Window("player.window.title", id: AppModel.playerWindowID) {
            configured(PlayerWindowView())
                .frame(minWidth: 720, minHeight: 405)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1120, height: 630)
        .windowResizability(.contentMinSize)
    }

    private func configured(_ content: some View) -> some View {
        content
            .environment(sessionManager)
            .environment(sessionManager.registry)
            .environment(settingsManager)
            .environment(downloadManager)
            .environment(libraryStore)
            .environment(seerrStore)
            .environment(appModel)
            .environment(sharePlayCoordinator)
            .environment(OfflineCoordinator.shared)
            .environment(externalPlaybackCallbackRouter)
    }
}
