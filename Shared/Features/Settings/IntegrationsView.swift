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

            ForEach(TrackerService.allCases) { service in
                NavigationLink {
                    TrackerSettingsView(service: service)
                } label: {
                    LabeledContent(service.displayName, value: TrackerCoordinator.shared.state(for: service).statusText)
                }
            }
        }
        .insetListStyle()
        .navigationTitle("settings.integrations.title")
    }
}
