import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @StateObject private var coordinator = MainCoordinator()
    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        TabView(selection: $coordinator.tab) {
            NavigationStack(path: coordinator.pathBinding(for: .home)) {
                HomeView(
                    viewModel: homeViewModel,
                    onSelectMedia: coordinator.showMediaDetail
                )
                .navigationDestination(for: MainCoordinator.Route.self) { route in
                    destination(for: route)
                }
            }
            .tabItem { Label("tabs.home", systemImage: "house.fill") }
            .tag(MainCoordinator.Tab.home)

            NavigationStack(path: coordinator.pathBinding(for: .search)) {
                SearchView()
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
            }
            .tabItem { Label("tabs.search", systemImage: "magnifyingglass") }
            .tag(MainCoordinator.Tab.search)

            NavigationStack(path: coordinator.pathBinding(for: .library)) {
                LibraryView(
                    viewModel: libraryViewModel,
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
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }
            .tag(MainCoordinator.Tab.library)
        }
        .tint(.brandPrimary)
        .tabViewStyle(.sidebarAdaptable)
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let ratingKey = coordinator.selectedRatingKey {
                PlayerWrapper(viewModel: PlayerViewModel(ratingKey: ratingKey, context: plexApiContext))
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    context: plexApiContext
                ),
                onPlay: { ratingKey in
                    coordinator.showPlayer(for: ratingKey)
                }
            )
        }
    }
}

#Preview {
    let context = PlexAPIContext()
    let session = SessionManager(context: context)

    return MainTabView(
        homeViewModel: HomeViewModel(context: context),
        libraryViewModel: LibraryViewModel(context: context)
    )
    .environment(context)
    .environment(session)
}
