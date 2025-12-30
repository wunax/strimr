import SwiftUI

struct MainTabTVView: View {
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(LibraryStore.self) private var libraryStore
    @StateObject private var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                NavigationStack(path: coordinator.pathBinding(for: .home)) {
                    HomeTVView(
                        viewModel: HomeViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchTVView(
                        viewModel: SearchViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            Tab("tabs.libraries", systemImage: "rectangle.stack.fill", value: MainCoordinator.Tab.library) {
                NavigationStack(path: coordinator.pathBinding(for: .library)) {
                    LibraryTVView(
                        viewModel: LibraryViewModel(
                            context: plexApiContext,
                            libraryStore: libraryStore
                        ),
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

            Tab("tabs.more", systemImage: "ellipsis.circle", value: MainCoordinator.Tab.more) {
                NavigationStack(path: coordinator.pathBinding(for: .more)) {
                    MoreTVView()
                        .navigationDestination(for: MoreTVRoute.self) { route in
                            switch route {
                            case .settings:
                                SettingsView()
                            }
                        }
                }
            }
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
