import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(\.openURL) var openURL
    @Environment(WatchTogetherViewModel.self) var watchTogetherViewModel
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
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
                        SeerrDiscoverView(
                            viewModel: SeerrDiscoverViewModel(store: seerrStore),
                            searchViewModel: SeerrSearchViewModel(store: seerrStore),
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )
                        .navigationDestination(for: SeerrMedia.self) { media in
                            SeerrMediaDetailView(
                                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                            )
                        }
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchView(
                        viewModel: SearchViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail,
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
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail,
                        )
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) {
                        destination(for: $0)
                    }
                }
            }

            TabSection {
                ForEach(navigationLibraries) { library in
                    Tab(
                        library.title,
                        systemImage: library.iconName,
                        value: MainCoordinator.Tab.libraryDetail(library.id),
                    ) {
                        NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.id))) {
                            LibraryDetailView(
                                library: library,
                                onSelectMedia: coordinator.showMediaDetail,
                            )
                            .navigationDestination(for: MainCoordinator.Route.self) {
                                destination(for: $0)
                            }
                        }
                    }
                }
            }
        }
        .tint(.brandPrimary)
        .environmentObject(coordinator)
        .task {
            try? await libraryStore.loadLibraries()
            watchTogetherViewModel.configurePlaybackLauncher(
                PlaybackLauncher(
                    context: plexApiContext,
                    coordinator: coordinator,
                    settingsManager: settingsManager,
                    openURL: { url in openURL(url) },
                ),
            )
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let playQueue = coordinator.selectedPlayQueue,
               let ratingKey = playQueue.selectedRatingKey
            {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        playQueue: playQueue,
                        ratingKey: ratingKey,
                        context: plexApiContext,
                        shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                    ),
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
                    context: plexApiContext,
                ),
                onPlay: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: type)
                    }
                },
                onPlayFromStart: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: type,
                            shouldResumeFromOffset: false,
                        )
                    }
                },
                onShuffle: { ratingKey, type in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: type,
                            shuffle: true,
                        )
                    }
                },
                onSelectMedia: coordinator.showMediaDetail,
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    context: plexApiContext,
                ),
                onSelectMedia: coordinator.showMediaDetail,
                onPlay: { ratingKey in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: .collection)
                    }
                },
                onShuffle: { ratingKey in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: .collection,
                            shuffle: true,
                        )
                    }
                },
            )
        case let .playlistDetail(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(
                    playlist: playlist,
                    context: plexApiContext,
                ),
                onSelectMedia: coordinator.showMediaDetail,
                onPlay: { ratingKey in
                    Task {
                        await playbackLauncher.play(ratingKey: ratingKey, type: .playlist)
                    }
                },
                onShuffle: { ratingKey in
                    Task {
                        await playbackLauncher.play(
                            ratingKey: ratingKey,
                            type: .playlist,
                            shuffle: true,
                        )
                    }
                },
            )
        }
    }

    private var playbackLauncher: PlaybackLauncher {
        PlaybackLauncher(
            context: plexApiContext,
            coordinator: coordinator,
            settingsManager: settingsManager,
            openURL: { url in openURL(url) },
        )
    }
}
