import SwiftUI

struct MainTabTVView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(\.openURL) var openURL
    @StateObject var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                NavigationStack(path: coordinator.pathBinding(for: .home)) {
                    HomeTVView(
                        viewModel: HomeViewModel(
                            context: plexApiContext,
                            settingsManager: settingsManager,
                            libraryStore: libraryStore,
                        ),
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            if settingsManager.interface.displaySeerrDiscoverTab {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
                        SeerrDiscoverTVView(
                            viewModel: SeerrDiscoverViewModel(store: seerrStore),
                            onSelectMedia: coordinator.showSeerrMediaDetail
                        )
                        .navigationDestination(for: SeerrMedia.self) { media in
                            SeerrMediaDetailTVView(
                                viewModel: SeerrMediaDetailViewModel(
                                    media: media,
                                    store: seerrStore
                                )
                            )
                        }
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchTVView(
                        viewModel: SearchViewModel(context: plexApiContext),
                        onSelectMedia: coordinator.showMediaDetail,
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
                            libraryStore: libraryStore,
                        ),
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                    .navigationDestination(for: Library.self) { library in
                        LibraryDetailView(
                            library: library,
                            onSelectMedia: coordinator.showMediaDetail,
                        )
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

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
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
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
        .environmentObject(coordinator)
        .task {
            try? await libraryStore.loadLibraries()
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
            if let playQueue = coordinator.selectedPlayQueue,
               let ratingKey = playQueue.selectedRatingKey
            {
                PlayerTVWrapper(
                    viewModel: PlayerViewModel(
                        playQueue: playQueue,
                        ratingKey: ratingKey,
                        context: plexApiContext,
                        shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                    ),
                    onExit: coordinator.resetPlayer,
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
            CollectionDetailTVView(
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
            PlaylistDetailTVView(
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

    private var navigationLibraries: [Library] {
        let libraryById = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryById[$0] }
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
