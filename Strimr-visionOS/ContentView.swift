import SwiftUI

struct ContentView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    init() {
        ErrorReporter.start()
    }

    var body: some View {
        switch sessionManager.status {
        case .hydrating:
            ProgressView("loading")
                .progressViewStyle(.circular)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        case .signedOut:
            SignInVisionView(
                viewModel: SignInViewModel(
                    sessionManager: sessionManager,
                    context: plexApiContext,
                ),
            )
        case .needsProfileSelection:
            NavigationStack {
                ProfileSwitcherVisionView(
                    viewModel: ProfileSwitcherViewModel(
                        context: plexApiContext,
                        sessionManager: sessionManager,
                    ),
                )
            }
        case .needsServerSelection:
            NavigationStack {
                SelectServerVisionView(
                    viewModel: ServerSelectionViewModel(
                        sessionManager: sessionManager,
                        context: plexApiContext,
                    ),
                )
            }
        case .ready:
            MainTabVisionView()
        }
    }
}
