import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexAPIContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(AppModel.self) private var appModel
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
                NavigationStack {
                    DownloadsView()
                }
            } else {
                sessionContent
            }
        }
        .onChange(of: offlineCoordinator.availability.hasNetworkPath) { _, hasNetworkPath in
            guard hasNetworkPath, sessionManager.status == .signedOut else { return }
            Task { await sessionManager.hydrate() }
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
        .onChange(of: appModel.playerPresentation?.id) { _, presentationID in
            guard presentationID != nil else { return }
            openWindow(id: AppModel.playerWindowID)
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

    @ViewBuilder
    private var sessionContent: some View {
        switch sessionManager.status {
        case .hydrating:
            ProgressView(sessionManager.loadingPhase.title)
                .controlSize(.large)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        case .needsProviderSelection:
            ProviderSelectionView()
        case .signedOut:
            SignInView(
                viewModel: SignInViewModel(
                    sessionManager: sessionManager,
                    context: plexAPIContext,
                ),
            )
        case .needsJellyfinAuthentication:
            JellyfinAuthenticationView()
        case .needsProfileSelection:
            ProfileSwitcherView(
                viewModel: ProfileSwitcherViewModel(
                    context: plexAPIContext,
                    sessionManager: sessionManager,
                ),
            )
        case .needsServerSelection:
            SelectServerView(
                viewModel: ServerSelectionViewModel(
                    sessionManager: sessionManager,
                    context: plexAPIContext,
                ),
            )
        case .ready:
            if let services = sessionManager.mediaServices {
                MainView(
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
