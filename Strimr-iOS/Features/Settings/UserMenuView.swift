import SwiftUI

@MainActor
struct UserMenuView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @EnvironmentObject private var coordinator: MainCoordinator
    @Environment(\.dismiss) private var dismiss

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
                            sessionManager: sessionManager,
                            onSelectMedia: { media in
                                dismiss()
                                coordinator.showMediaDetail(media)
                            },
                        )
                    } label: {
                        Label("tabs.favorites", systemImage: "star.fill")
                    }
                }
            }

            Section {
                if sessionManager.profiles.count > 1 {
                    Button {
                        dismiss()
                        sessionManager.requestProfileSelection()
                    } label: {
                        Label("common.actions.switchProfile", systemImage: "person.2.circle")
                    }
                    .buttonStyle(.plain)
                    .disabled(offlineCoordinator.isFullyOffline)

                    if offlineCoordinator.isFullyOffline {
                        Text("offline.menu.switchUnavailable")
                            .font(.footnote)
                            .foregroundStyle(.secondary)
                    }
                }

                if sessionManager.canManageAccounts {
                    NavigationLink {
                        ProfilesSettingsView()
                    } label: {
                        Label("profiles.title", systemImage: "person.crop.circle")
                    }

                    NavigationLink {
                        AccountsSettingsView()
                    } label: {
                        Label("settings.accounts.title", systemImage: "server.rack")
                    }
                }
            }
        }
        .listStyle(.insetGrouped)
        .navigationTitle(sessionManager.activeProfile?.name ?? String(localized: "tabs.more"))
    }
}
