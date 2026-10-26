import SwiftUI

@main
struct StrimrApp: App {
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var mediaFocusModel: MediaFocusModel
    @State private var seerrStore: SeerrStore
    @State private var seerrFocusModel: SeerrFocusModel
    @State private var sharePlayCoordinator: SharePlayCoordinator
    @State private var topShelfDeepLinkRouter = TopShelfDeepLinkRouter()
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
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        _mediaFocusModel = State(initialValue: MediaFocusModel())
        #if DEBUG
            _seerrStore = State(initialValue: SeerrStore(userDefaults: demoStores?.defaults ?? .standard))
        #else
            _seerrStore = State(initialValue: SeerrStore())
        #endif
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
                .environment(seerrFocusModel)
                .environment(sharePlayCoordinator)
                .environment(topShelfDeepLinkRouter)
                .environment(externalPlaybackCallbackRouter)
                .preferredColorScheme(.dark)
                .onOpenURL { url in
                    if !externalPlaybackCallbackRouter.receive(url) {
                        topShelfDeepLinkRouter.receive(url)
                    }
                }
        }
    }
}
