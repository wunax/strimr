import SwiftUI

struct ContentView: View {
    @Environment(\.openWindow) private var openWindow
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexAPIContext
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(MacAppModel.self) private var appModel

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            switch sessionManager.status {
            case .hydrating:
                ProgressView("loading")
                    .controlSize(.large)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                MacSignInView(
                    viewModel: MacSignInViewModel(
                        sessionManager: sessionManager,
                        context: plexAPIContext,
                    ),
                )
            case .needsProfileSelection:
                MacProfileSwitcherView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexAPIContext,
                        sessionManager: sessionManager,
                    ),
                )
            case .needsServerSelection:
                MacServerSelectionView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexAPIContext,
                    ),
                )
            case .ready:
                MacMainView(
                    homeViewModel: HomeViewModel(
                        context: plexAPIContext,
                        settingsManager: settingsManager,
                        libraryStore: libraryStore,
                    ),
                    libraryViewModel: LibraryViewModel(
                        context: plexAPIContext,
                        libraryStore: libraryStore,
                    ),
                )
            }
        }
        .onChange(of: appModel.playerPresentation?.id) { _, presentationID in
            guard presentationID != nil else { return }
            openWindow(id: MacAppModel.playerWindowID)
        }
    }
}
