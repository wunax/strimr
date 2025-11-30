import SwiftUI

@main
struct StrimrApp: App {
    @State private var plexApiManager: PlexAPIManager
    @State private var sessionManager: SessionManager

    init() {
        let api = PlexAPIManager()
        _plexApiManager = State(initialValue: api)
        _sessionManager = State(initialValue: SessionManager(apiManager: api))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(plexApiManager)
                .environment(sessionManager)
                .preferredColorScheme(.dark)
        }
    }
}
