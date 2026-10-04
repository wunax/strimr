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
        _libraryStore = State(initialValue: LibraryStore(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
        _mediaFocusModel = State(initialValue: MediaFocusModel())
        _seerrStore = State(initialValue: SeerrStore())
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
                .preferredColorScheme(.dark)
                .onOpenURL(perform: topShelfDeepLinkRouter.receive)
        }
    }
}
