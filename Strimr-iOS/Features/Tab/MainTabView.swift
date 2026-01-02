import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(\.openURL) var openURL
    @StateObject var coordinator = MainCoordinator()
    @State var homeViewModel: HomeViewModel
    @State var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                NavigationStack(path: coordinator.pathBinding(for: .home)) {
                    HomeView(
                        viewModel: homeViewModel,
                        onSelectMedia: coordinator.showMediaDetail
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchView(
                        viewModel: SearchViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            Tab("tabs.libraries", systemImage: "rectangle.stack.fill", value: MainCoordinator.Tab.library) {
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
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            ForEach(navigationLibraries) { library in
                Tab(library.title, systemImage: library.iconName, value: MainCoordinator.Tab.libraryDetail(library.id)) {
                    NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.id))) {
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail
                        )
                        .navigationDestination(for: MainCoordinator.Route.self) {
                            destination(for: $0)
                        }
                    }
                }
            }
        }
        .tint(.brandPrimary)
        .environmentObject(coordinator)
        .task {
            try? await libraryStore.loadLibraries()
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let ratingKey = coordinator.selectedRatingKey {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        ratingKey: ratingKey,
                        context: plexApiContext,
                        shouldResumeFromOffset: coordinator.shouldResumeFromOffset
                    )
                )
            }
        }
    }

    private var navigationLibraries: [Library] {
        let libraryById = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryById[$0] }
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
                    handlePlay(ratingKey: ratingKey)
                },
                onPlayFromStart: { ratingKey in
                    handlePlay(ratingKey: ratingKey, shouldResumeFromOffset: false)
                },
                onSelectMedia: coordinator.showMediaDetail
            )
        }
    }
}
