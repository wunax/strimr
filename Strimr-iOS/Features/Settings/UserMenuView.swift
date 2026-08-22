import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MediaServices.self) private var mediaServices
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.dismiss) private var dismiss
    @State private var isShowingLogoutConfirmation = false

    var body: some View {
        List {
            Section {
                NavigationLink {
                    SettingsView()
                } label: {
                    Label("settings.title", systemImage: "gearshape.fill")
                }

                if !settingsManager.interface.displayDownloadsTab {
                    NavigationLink {
                        DownloadsView()
                    } label: {
                        Label("downloads.title", systemImage: "arrow.down.circle.fill")
                    }
                }

                if !settingsManager.interface.displayFavoritesTab {
                    NavigationLink {
                        FavoritesView(
                            services: mediaServices,
                            onSelectMedia: { media in
                                dismiss()
                                coordinator.showMediaDetail(media)
                            },
                        )
                    } label: {
                        Label("tabs.favorites", systemImage: "star.fill")
                    }
                }

                if sessionManager.mediaServices?.capabilities.profiles == true {
                    Button {
                        Task { await sessionManager.requestProfileSelection() }
                    } label: {
                        Label("common.actions.switchProfile", systemImage: "person.2.circle")
                    }
                    .buttonStyle(.plain)
                }

                if sessionManager.provider == .plex {
                    Button {
                        Task { await sessionManager.requestServerSelection() }
                    } label: {
                        Label("common.actions.switchServer", systemImage: "server.rack")
                    }
                    .buttonStyle(.plain)
                }

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
