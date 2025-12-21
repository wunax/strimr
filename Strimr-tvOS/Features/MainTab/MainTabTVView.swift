import SwiftUI

struct MainTabTVView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext

    var body: some View {
        TabView {
            NavigationStack {
                HomeTVView(
                    viewModel: HomeViewModel(context: plexApiContext)
                )
            }
            .tabItem { Label("tabs.home", systemImage: "house.fill") }

            NavigationStack {
                SearchTVView(
                    viewModel: SearchViewModel(context: plexApiContext)
                )
            }
            .tabItem { Label("tabs.search", systemImage: "magnifyingglass") }

            NavigationStack {
                TVSectionPlaceholder(
                    title: "tabs.libraries",
                    subtitle: "Browse your libraries soon."
                )
            }
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }

            NavigationStack {
                moreView
            }
            .tabItem { Label("tabs.more", systemImage: "ellipsis.circle") }
        }
    }

    private var moreView: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text("tabs.more")
                        .font(.largeTitle.bold())
                    Text("Manage your session while we finish the tvOS experience.")
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 8)

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
                        Label("common.actions.signOut", systemImage: "rectangle.portrait.and.arrow.right")
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

private struct TVSectionPlaceholder: View {
    var title: LocalizedStringKey
    var subtitle: LocalizedStringKey

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.largeTitle.bold())
                Text(subtitle)
                    .foregroundStyle(.secondary)
                    .font(.title3)

                Spacer()
            }
            .padding(48)
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    return MainTabTVView()
        .environment(context)
        .environment(SessionManager(context: context))
}
