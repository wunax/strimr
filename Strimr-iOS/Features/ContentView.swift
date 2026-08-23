import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(DownloadManager.self) private var downloadManager

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            if downloadManager.shouldForceOfflineDownloads {
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
        .onChange(of: downloadManager.isOffline) { _, isOffline in
            guard !isOffline else { return }
            guard sessionManager.status == .signedOut else { return }
            Task {
                await sessionManager.hydrate()
            }
        }
        .onChange(of: sessionManager.mediaServices?.identity, initial: true) { _, _ in
            if let services = sessionManager.mediaServices {
                downloadManager.register(services: services)
            }
        }
    }
}
