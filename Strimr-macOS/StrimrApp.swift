import SwiftUI

@main
struct StrimrMacApp: App {
    @State private var plexAPIContext: PlexAPIContext
    @State private var sessionManager: SessionManager
    @State private var settingsManager: SettingsManager
    @State private var libraryStore: LibraryStore
    @State private var seerrStore: SeerrStore
    @State private var appModel: MacAppModel

    init() {
        let context = PlexAPIContext()
        let libraryStore = LibraryStore(context: context)
        let sessionManager = SessionManager(context: context, libraryStore: libraryStore)

        _plexAPIContext = State(initialValue: context)
        _sessionManager = State(initialValue: sessionManager)
        _settingsManager = State(initialValue: SettingsManager())
        _libraryStore = State(initialValue: libraryStore)
        _seerrStore = State(initialValue: SeerrStore())
        _appModel = State(initialValue: MacAppModel())
    }

    var body: some Scene {
        WindowGroup {
            configured(ContentView())
                .frame(minWidth: 900, minHeight: 620)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1280, height: 820)

        Window("player.window.title", id: MacAppModel.playerWindowID) {
            configured(MacPlayerWindowView())
                .frame(minWidth: 720, minHeight: 405)
                .preferredColorScheme(.dark)
        }
        .defaultSize(width: 1120, height: 630)
        .windowResizability(.contentMinSize)
    }

    private func configured<Content: View>(_ content: Content) -> some View {
        content
            .environment(plexAPIContext)
            .environment(sessionManager)
            .environment(settingsManager)
            .environment(libraryStore)
            .environment(seerrStore)
            .environment(appModel)
    }
}
