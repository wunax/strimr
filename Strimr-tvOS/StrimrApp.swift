import SwiftUI

@main
struct StrimrApp: App {
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mediaFocusModel: MediaFocusModel
    @State private var seerrStore: SeerrStore
    @State private var exploreRegistry: ExploreSourceRegistry
    @State private var seerrFocusModel: SeerrFocusModel
    @State private var sharePlayCoordinator: SharePlayCoordinator
    @State private var externalPlaybackCallbackRouter = ExternalPlaybackCallbackRouter()

    init() {
        let favoritesStore = FavoritesStore()
        #if DEBUG
            let demoStores = DemoStores.makeIfEnabled()
            let settingsManager = demoStores.map { SettingsManager(userDefaults: $0.defaults) } ?? SettingsManager()
            if demoStores != nil, let style = DemoMode.playerControlsStyle {
                settingsManager.setPlayerControlsStyle(style)
            }
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
        AppIntentsEnvironment.sessionManager = sessionManager
        _settingsManager = State(initialValue: settingsManager)
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        _mediaFocusModel = State(initialValue: MediaFocusModel())
        #if DEBUG
            let seerrStore = SeerrStore(userDefaults: demoStores?.defaults ?? .standard)
        #else
            let seerrStore = SeerrStore()
        #endif
        _seerrStore = State(initialValue: seerrStore)
        _exploreRegistry = State(initialValue: ExploreSourceRegistry(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
            seerrStore: seerrStore,
        ))
        _seerrFocusModel = State(initialValue: SeerrFocusModel())
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
                .environment(libraryStore)
                .environment(mediaFocusModel)
                .environment(seerrStore)
                .environment(exploreRegistry)
                .environment(seerrFocusModel)
                .environment(sharePlayCoordinator)
                .environment(DeepLinkRouter.shared)
                .environment(externalPlaybackCallbackRouter)
                .flushesTrackerQueue()
                .toastHost()
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if externalPlaybackCallbackRouter.receive(url) {
                        sessionManager.didReturnFromExternalPlayback()
                    } else {
                        sessionManager.sceneWillReturnFromBackground()
                        DeepLinkRouter.shared.receive(url)
                    }
                }
        }
    }
}
