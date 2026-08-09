import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

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
            case .signedOut:
                SignInView(
                    viewModel: SignInViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
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
                MainTabView()
            }
        }
    }
}
