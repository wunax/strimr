import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            switch sessionManager.status {
            case .hydrating:
                ProgressView("loading")
                    .progressViewStyle(.circular)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .signedOut:
                SignInView(
                    viewModel: SignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext
                    )
                )
            case .needsProfileSelection:
                NavigationStack {
                    ProfileSwitcherView(
                        viewModel: ProfileSwitcherViewModel(
                            context: plexApiContext,
                            sessionManager: sessionManager
                        )
                    )
                }
            case .needsServerSelection:
                SelectServerView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext
                    )
                )
            case .ready:
                MainTabView(
                    homeViewModel: HomeViewModel(context: plexApiContext),
                    libraryViewModel: LibraryViewModel(
                        context: plexApiContext,
                        libraryStore: libraryStore
                    )
                )
            }
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    ContentView()
        .environment(context)
        .environment(SessionManager(context: context))
        .environment(LibraryStore(context: context))
}
