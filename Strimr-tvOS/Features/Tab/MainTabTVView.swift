import SwiftUI

struct MainTabTVView: View {
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
            .tabItem { Label("tabs.libraries", systemImage: "rectangle.stack.fill") }
            .tag(MainCoordinator.Tab.library)

            NavigationStack(path: coordinator.pathBinding(for: .more)) {
                MoreTVView()
                    .navigationDestination(for: MoreTVRoute.self) { route in
                        switch route {
                        case .settings:
                            SettingsView()
                        }
                    }
            }
            .tabItem { Label("tabs.more", systemImage: "ellipsis.circle") }
            .tag(MainCoordinator.Tab.more)
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let ratingKey = coordinator.selectedRatingKey {
                PlayerTVWrapper(
                    viewModel: PlayerViewModel(ratingKey: ratingKey, context: plexApiContext),
                    onExit: coordinator.resetPlayer
                )
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        switch route {
        case let .mediaDetail(media):
            MediaDetailTVView(
                viewModel: MediaDetailViewModel(media: media, context: plexApiContext),
                onPlay: { ratingKey in
                    coordinator.showPlayer(for: ratingKey)
                },
                onSelectMedia: coordinator.showMediaDetail
            )
        }
    }
}
