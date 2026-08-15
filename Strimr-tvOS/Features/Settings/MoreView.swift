import SwiftUI

enum MoreRoute: Hashable {
    case settings
}

@MainActor
struct MoreView: View {
    @Environment(SessionManager.self) private var sessionManager

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

                    if sessionManager.mediaServices?.capabilities.profiles == true {
                        Button {
                            Task { await sessionManager.requestProfileSelection() }
                        } label: {
                            Label("common.actions.switchProfile", systemImage: "person.2.fill")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    if sessionManager.provider == .plex {
                        Button {
                            Task { await sessionManager.requestServerSelection() }
                        } label: {
                            Label("serverSelection.title", systemImage: "server.rack")
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .padding()
                        }
                        .buttonStyle(.borderedProminent)
                    }

                    Button {
                        Task { await sessionManager.signOut() }
                    } label: {
                        Label("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    Spacer()
                }
                .padding(48)
            }
        }
    }
}
