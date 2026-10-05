import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            switch sessionManager.status {
            case .hydrating:
                ProgressView(sessionManager.loadingPhase.title)
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
            case .needsAccount:
                AccountSetupView(purpose: .firstLaunch, sessionManager: sessionManager)
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(viewModel: ProfileSwitcherViewModel(sessionManager: sessionManager))
                }
            case .migrationFailed:
                MigrationFailedView()
            case .ready:
                MainTabView(
                    homeViewModel: HomeViewModel(sessionManager: sessionManager, settingsManager: settingsManager),
                    libraryViewModel: LibraryViewModel(
                        sessionManager: sessionManager,
                        libraryStore: libraryStore,
                        settingsManager: settingsManager,
                    ),
                )
                .id(registry.generation)
            }
        }
        .onChange(of: registry.readyServers) { _, _ in
            sessionManager.updateTopShelf()
        }
        .onChange(of: sessionManager.status) { _, status in
            if status != .ready {
                sessionManager.updateTopShelf()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                registry.retryUnavailable()
            }
        }
    }
}
