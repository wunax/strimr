import SwiftUI

enum MoreRoute: Hashable {
    case settings
    case favorites
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
                        .font(.heroTitle)
                        .foregroundStyle(.textPrimary)

                    NavigationLink(value: MoreRoute.settings) {
                        Label("settings.title", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.bordered)

                    if !settingsManager.interface.displayLibrariesTab {
                        NavigationLink(value: MainCoordinator.Route.libraryBrowser) {
                            Label("tabs.libraries", systemImage: "rectangle.stack.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                    }

                    if !settingsManager.interface.displayFavoritesTab {
                        NavigationLink(value: MoreRoute.favorites) {
                            Label("tabs.favorites", systemImage: "star.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                    }

                    if sessionManager.profiles.count > 1 {
                        Button {
                            sessionManager.requestProfileSelection()
                        } label: {
                            Label("common.actions.switchProfile", systemImage: "person.2.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.bordered)
                    }

                    Spacer()
                }
                .padding(48)
            }
        }
    }
}
