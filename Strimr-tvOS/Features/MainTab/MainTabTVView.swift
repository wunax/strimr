import SwiftUI

struct MainTabTVView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $coordinator.tab) {
            NavigationStack(path: coordinator.pathBinding(for: .home)) {
                HomeTVView(
                    viewModel: HomeViewModel(context: plexApiContext),
                    onSelectMedia: coordinator.showMediaDetail
                )
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("tabs.home", systemImage: "house.fill") }
            .tag(MainCoordinator.Tab.home)

            NavigationStack(path: coordinator.pathBinding(for: .search)) {
                SearchTVView(
                    viewModel: SearchViewModel(context: plexApiContext),
                    onSelectMedia: coordinator.showMediaDetail
                )
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("tabs.search", systemImage: "magnifyingglass") }
            .tag(MainCoordinator.Tab.search)

            NavigationStack(path: coordinator.pathBinding(for: .library)) {
                ZStack {
                    Color("Background")
                        .ignoresSafeArea()

                    LibraryTVView(
                        viewModel: LibraryViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail
                        )
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }
            .tag(MainCoordinator.Tab.library)

            NavigationStack {
                moreView
            }
            .tabItem { Label("tabs.more", systemImage: "ellipsis.circle") }
            .tag(MainCoordinator.Tab.more)
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

    @ViewBuilder
    func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailTVView(
                viewModel: MediaDetailViewModel(media: media, context: plexApiContext),
                onSelectMedia: coordinator.showMediaDetail
            )
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    return MainTabTVView()
        .environment(context)
        .environment(SessionManager(context: context))
}
