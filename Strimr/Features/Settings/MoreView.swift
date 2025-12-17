import SwiftUI

enum MoreRoute: Hashable {
    case settings
}

@MainActor
struct MoreView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isShowingLogoutConfirmation = false
    var onSwitchProfile: () -> Void = {}
    var onSwitchServer: () -> Void = {}

    var body: some View {
        List {
            Section {
                NavigationLink(value: MoreRoute.settings) {
                    Label("settings.title", systemImage: "gearshape.fill")
                }

                Button(action: onSwitchProfile) {
                    Label("common.actions.switchProfile", systemImage: "person.2.circle")
                }
                .buttonStyle(.plain)

                Button(action: onSwitchServer) {
                    Label("common.actions.switchServer", systemImage: "server.rack")
                }
                .buttonStyle(.plain)

                Button {
                    isShowingLogoutConfirmation = true
                } label: {
                    Label("common.actions.logOut", systemImage: "arrow.backward.circle")
                }
                .buttonStyle(.plain)
                .tint(.red)
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle("tabs.more")
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
    }
}

#Preview {
    NavigationStack {
        MoreView()
            .navigationDestination(for: MoreRoute.self) { route in
                switch route {
                case .settings:
                    EmptyView()
                }
            }
    }
}
