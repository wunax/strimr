import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexAPIContext: PlexAPIContext
    @State private var jellyfinAPIContext: JellyfinAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var downloadManager: DownloadManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var appModel: AppModel
    @State private var sharePlayCoordinator: SharePlayCoordinator

    init() {
        let context = PlexAPIContext()
        let jellyfinContext = JellyfinAPIContext()
        let libraryStore = LibraryStore(context: context)
        let sessionManager = SessionManager(
            context: context,
            jellyfinContext: jellyfinContext,
            libraryStore: libraryStore,
        )

        _plexAPIContext = State(initialValue: context)
        _jellyfinAPIContext = State(initialValue: jellyfinContext)
        _sessionManager = State(initialValue: sessionManager)
        let settingsManager = SettingsManager()
        _settingsManager = State(initialValue: settingsManager)
        _downloadManager = State(initialValue: DownloadManager(settingsManager: settingsManager))
        _libraryStore = State(initialValue: libraryStore)
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
            .environment(plexAPIContext)
            .environment(jellyfinAPIContext)
            .environment(sessionManager)
            .environment(settingsManager)
            .environment(downloadManager)
            .environment(libraryStore)
            .environment(seerrStore)
            .environment(appModel)
            .environment(sharePlayCoordinator)
    }
}
