import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
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
                case .needsProviderSelection:
                    ProviderSelectionView()
                case .signedOut:
                    NavigationStack {
                        SignInView(
                            viewModel: SignInViewModel(
                                sessionManager: sessionManager,
                                context: plexApiContext,
                            ),
                        )
                    }
                case .needsJellyfinAuthentication:
                    NavigationStack {
                        JellyfinAuthenticationView()
                    }
                case .needsProfileSelection:
                    NavigationStack {
                        ProfileSwitcherView(
                            viewModel: ProfileSwitcherViewModel(
                                context: plexApiContext,
                                sessionManager: sessionManager,
                            ),
                        )
                    }
                case .needsServerSelection:
                    NavigationStack {
                        SelectServerView(
                            viewModel: ServerSelectionViewModel(
                                sessionManager: sessionManager,
                                context: plexApiContext,
                            ),
                        )
                    }
                case .ready:
                    if let services = sessionManager.mediaServices {
                        MainTabView(
                            homeViewModel: HomeViewModel(
                                services: services,
                                settingsManager: settingsManager,
                                libraryStore: libraryStore,
                            ),
                            libraryViewModel: LibraryViewModel(
                                services: services,
                                libraryStore: libraryStore,
                            ),
                        )
                        .environment(services)
                    } else {
                        ProgressView(sessionManager.loadingPhase.title)
                    }
                }
            }
        }
        .onChange(of: offlineCoordinator.availability.hasNetworkPath) { _, hasNetworkPath in
            guard hasNetworkPath else { return }
            guard sessionManager.status == .signedOut else { return }
            Task {
                await sessionManager.hydrate()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                offlineCoordinator.availability.refresh()
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
        .onChange(of: sessionManager.mediaServices.map(ObjectIdentifier.init), initial: true) { _, _ in
            OfflineCoordinator.shared.activate(services: sessionManager.mediaServices)
            downloadManager.activateSession(services: sessionManager.mediaServices)
        }
    }

    /// Without a restorable session and without network, downloads are shown directly at launch.
    private var showsStaticDownloads: Bool {
        guard !offlineCoordinator.availability.hasNetworkPath, downloadManager.playableCount > 0 else { return false }
        switch sessionManager.status {
        case .signedOut, .needsProviderSelection, .needsJellyfinAuthentication:
            return true
        case .hydrating, .needsProfileSelection, .needsServerSelection, .ready:
            return false
        }
    }
}
