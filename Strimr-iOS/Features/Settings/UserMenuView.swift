import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(MediaServices.self) private var mediaServices
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.dismiss) private var dismiss
    @Environment(DownloadManager.self) private var downloadManager
    @State private var isShowingLogoutConfirmation = false
    @State private var signOutFlow = SignOutFlow()

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
                    .disabled(offlineCoordinator.isFullyOffline)
                }

                if sessionManager.provider == .plex {
                    Button {
                        Task { await sessionManager.requestServerSelection() }
                    } label: {
                        Label("common.actions.switchServer", systemImage: "server.rack")
                    }
                    .buttonStyle(.plain)
                    .disabled(offlineCoordinator.isFullyOffline)
                }

                if offlineCoordinator.isFullyOffline {
                    Text("offline.menu.switchUnavailable")
                        .font(.footnote)
                        .foregroundStyle(.secondary)
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
                Task { await signOutFlow.begin(sessionManager: sessionManager, downloadManager: downloadManager) }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .signOutDownloadsPrompt(signOutFlow)
        .disabled(signOutFlow.isSigningOut)
    }
}
