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

        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: DownloadManager(settingsManager: settingsManager))
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        _seerrStore = State(initialValue: SeerrStore())
        _appModel = State(initialValue: AppModel())
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
    }
}
