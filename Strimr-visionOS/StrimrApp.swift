import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var watchTogetherViewModel: WatchTogetherViewModel
    @State private var sharePlayViewModel: SharePlayViewModel

    init() {
        let context = PlexAPIContext()
        let store = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: store)
        _plexApiContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: store)
        _seerrStore = State(initialValue: SeerrStore())
        _watchTogetherViewModel = State(initialValue: WatchTogetherViewModel(
            sessionManager: sessionManager,
            context: context,
        ))
        _sharePlayViewModel = State(initialValue: SharePlayViewModel(context: context))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiContext)
                .environment(sessionManager)
                .environment(settingsManager)
                .environment(libraryStore)
                .environment(seerrStore)
                .environment(watchTogetherViewModel)
                .environment(sharePlayViewModel)
                .task {
                    sharePlayViewModel.observeSessions()
                }
        }
        .windowStyle(.automatic)

        WindowGroup(id: "player", for: PlayerLaunchData.self) { $data in
            if let data {
                PlayerVisionWrapper(launchData: data)
                    .environment(plexApiContext)
                    .environment(settingsManager)
                    .environment(watchTogetherViewModel)
                    .environment(sharePlayViewModel)
            }
        }
        .windowStyle(.plain)
        .defaultSize(width: 1920, height: 1080)
    }
}
