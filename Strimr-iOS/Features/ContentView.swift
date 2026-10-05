import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(DownloadManager.self) private var downloadManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(\.scenePhase) private var scenePhase

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            if showsStaticDownloads {
                OfflineDownloadsRootView()
            } else {
                switch sessionManager.status {
                case .hydrating:
                    ProgressView(sessionManager.loadingPhase.title)
                        .progressViewStyle(.circular)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
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
        }
        .onChange(of: offlineCoordinator.availability.hasNetworkPath) { _, hasNetworkPath in
            guard hasNetworkPath, sessionManager.status == .migrationFailed else { return }
            Task {
                await sessionManager.hydrate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                offlineCoordinator.availability.refresh()
                registry.retryUnavailable()
            case .background:
                offlineCoordinator.evictCacheIfNeeded()
            case .inactive:
                break
            @unknown default:
                break
            }
        }
        .onChange(of: settingsManager.downloads.offlineCacheLimitMB, initial: true) { _, megabytes in
            offlineCoordinator.setCacheLimit(megabytes: megabytes)
        }
        .onChange(of: registry.connectedServices.map(ObjectIdentifier.init), initial: true) { _, _ in
            downloadManager.activateSession(services: registry.connectedServices)
        }
    }

    /// Without a restorable session and without network, downloads are shown directly at launch.
    private var showsStaticDownloads: Bool {
        guard !offlineCoordinator.availability.hasNetworkPath, downloadManager.playableCount > 0 else { return false }
        switch sessionManager.status {
        case .needsAccount, .migrationFailed:
            return true
        case .hydrating, .needsProfileSelection, .ready:
            return false
        }
    }
}
