import SwiftUI

@MainActor
struct IntegrationsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SeerrStore.self) private var seerrStore

    var body: some View {
        List {
            NavigationLink("integrations.seerr.title") {
                SeerrView(
                    viewModel: SeerrViewModel(
                        store: seerrStore,
                        sessionManager: sessionManager,
                        sessionService: SeerrSessionService(),
                    ),
                )
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("settings.integrations.title")
    }
}
