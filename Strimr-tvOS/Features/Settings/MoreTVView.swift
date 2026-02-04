import SwiftUI

enum MoreTVRoute: Hashable {
    case settings
    case watchTogether
}

@MainActor
struct MoreTVView: View {
    @Environment(SessionManager.self) private var sessionManager

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("tabs.more")
                        .font(.largeTitle.bold())

                    NavigationLink(value: MoreTVRoute.settings) {
                        Label("settings.title", systemImage: "gearshape.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    NavigationLink(value: MoreTVRoute.watchTogether) {
                        Label("watchTogether.title", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await sessionManager.requestProfileSelection() }
                    } label: {
                        Label("common.actions.switchProfile", systemImage: "person.2.fill")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    Button {
                        Task { await sessionManager.requestServerSelection() }
                    } label: {
                        Label("serverSelection.title", systemImage: "server.rack")
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                    }
                    .buttonStyle(.borderedProminent)

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
