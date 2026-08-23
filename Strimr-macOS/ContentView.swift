import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexAPIContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(AppModel.self) private var appModel
    @Environment(DownloadManager.self) private var downloadManager

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

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
        .onChange(of: appModel.playerPresentation?.id) { _, presentationID in
            guard presentationID != nil else { return }
            openWindow(id: AppModel.playerWindowID)
        }
        .onChange(of: sessionManager.mediaServices?.identity, initial: true) { _, _ in
            if let services = sessionManager.mediaServices {
                downloadManager.register(services: services)
            }
        }
    }
}
