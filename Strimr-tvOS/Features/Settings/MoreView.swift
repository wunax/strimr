import SwiftUI

enum MoreRoute: Hashable {
    case settings
    case favorites
    case profiles
    case accounts
}

@MainActor
struct MoreView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("tabs.more")
                        .font(.largeTitle.bold())

                    NavigationLink(value: MoreRoute.settings) {
                        Label("settings.title", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    if !settingsManager.interface.displayFavoritesTab {
                        NavigationLink(value: MoreRoute.favorites) {
                            Label("tabs.favorites", systemImage: "star.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if sessionManager.profiles.count > 1 {
                        Button {
                            sessionManager.requestProfileSelection()
                        } label: {
                            Label("common.actions.switchProfile", systemImage: "person.2.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if sessionManager.canManageAccounts {
                        NavigationLink(value: MoreRoute.profiles) {
                            Label("profiles.title", systemImage: "person.crop.circle")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)

                        NavigationLink(value: MoreRoute.accounts) {
                            Label("settings.accounts.title", systemImage: "server.rack")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Spacer()
                }
                .padding(48)
            }
        }
    }
}
