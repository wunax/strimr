import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("settings.title", systemImage: "gearshape.fill")
                }

                NavigationLink {
                    WatchTogetherView()
                } label: {
                    Label("watchTogether.title", systemImage: "person.2.fill")
                }

                Button {
                    Task { await sessionManager.requestProfileSelection() }
                } label: {
                    Label("common.actions.switchProfile", systemImage: "person.2.circle")
                }
                .buttonStyle(.plain)

                Button {
                    Task { await sessionManager.requestServerSelection() }
                } label: {
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
