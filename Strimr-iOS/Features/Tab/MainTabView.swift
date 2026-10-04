import SwiftUI

struct MainTabView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(ServerRegistry.self) var registry
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var coordinator = MainCoordinator()
    @State var homeViewModel: HomeViewModel
    @State var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        tabView
            .environmentObject(coordinator)
            .task {
                sharePlayCoordinator.configurePlaybackPresenter(coordinator)
                try? await libraryStore.loadLibraries()
            }
            .task(id: registry.readyServers) {
                await homeViewModel.syncServers()
                await libraryViewModel.syncServers()
                await refreshLiveTVAvailability()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshLiveTVAvailability() }
            }
            .onChange(of: settingsManager.interface.displayLiveTVTab) { _, isDisplayed in
                if !isDisplayed {
                    coordinator.resetLiveTVNavigation()
                }
            }
            .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: playerDidClose) {
                if let queue = coordinator.selectedMediaQueue,
                   let services = coordinator.selectedMediaServices
                {
                    PlayerWrapper(
                        viewModel: PlayerViewModel(
                            queue: queue,
                            services: services,
                            shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                        ),
                    )
                    .environment(services)
                } else if let context = coordinator.selectedLiveTVContext,
                          let services = coordinator.selectedMediaServices
                {
                    PlayerWrapper(viewModel: PlayerViewModel(live: context, services: services))
                        .environment(services)
                } else if let request = coordinator.selectedLocalPlayback {
                    PlayerWrapper(viewModel: PlayerViewModel(request: request))
                }
            }
    }

    /// Only the server of the item that was played is reloaded, to update Reprendre and Next Up.
    private func playerDidClose() {
        let server = coordinator.selectedMediaServices?.identity
        coordinator.resetPlayer()
        if let server {
            Task { await homeViewModel.refresh(server: server) }
        }
    }

    private func refreshLiveTVAvailability() async {
        await registry.refreshLiveTVAvailability()
        if registry.liveTVServices.isEmpty {
            coordinator.resetLiveTVNavigation()
        }
    }

    private var tabView: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                homeTabContent
            }

            if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    discoverTabContent
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                searchTabContent
            }

            if settingsManager.interface.displayDownloadsTab {
                Tab("downloads.title", systemImage: "arrow.down.circle.fill", value: MainCoordinator.Tab.downloads) {
                    downloadsTabContent
                }
            }

            Tab("tabs.libraries", systemImage: "rectangle.stack.fill", value: MainCoordinator.Tab.library) {
                libraryTabContent
            }

            if !registry.liveTVServices.isEmpty, settingsManager.interface.displayLiveTVTab {
                Tab("livetv.title", systemImage: "tv", value: MainCoordinator.Tab.liveTV) {
                    liveTVTabContent
                }
            }

            if settingsManager.interface.displayFavoritesTab {
                Tab("tabs.favorites", systemImage: "star.fill", value: MainCoordinator.Tab.favorites) {
                    favoritesTabContent
                }
            }

            TabSection {
                ForEach(libraryStore.navigationLibraries, id: \.identity) { library in
                    Tab(
                        library.title,
                        systemImage: library.iconName,
                        value: MainCoordinator.Tab.libraryDetail(library.identity),
                    ) {
                        libraryDetailTabContent(library)
                    }
                }
            }
        }
    }

    private var homeTabContent: some View {
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

    private var discoverTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
            SeerrDiscoverView(
                viewModel: SeerrDiscoverViewModel(store: seerrStore),
                searchViewModel: SeerrSearchViewModel(store: seerrStore),
                onSelectMedia: coordinator.showSeerrMediaDetail,
            )
            .unavailableWhenOffline()
            .navigationDestination(for: SeerrMedia.self) { media in
                SeerrMediaDetailView(
                    viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                )
            }
        }
    }

    private var searchTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .search)) {
            SearchView(
                viewModel: SearchViewModel(sessionManager: sessionManager),
                onSelectMedia: { coordinator.showMediaDetail($0.media) },
            )
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    private var libraryTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .library)) {
            LibraryView(
                viewModel: libraryViewModel,
                onSelectMedia: coordinator.showMediaDetail,
            )
            .navigationDestination(for: Library.self) { library in
                ServerScopedView(server: library.server) { _ in
                    LibraryDetailView(
                        library: library,
                        onSelectMedia: coordinator.showMediaDetail,
                    )
                }
            }
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    private var downloadsTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .downloads)) {
            DownloadsView()
        }
    }

    private var favoritesTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .favorites)) {
            FavoritesView(
                sessionManager: sessionManager,
                onSelectMedia: coordinator.showMediaDetail,
            )
            .unavailableWhenOffline()
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    private var liveTVTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .liveTV)) {
            LiveTVServersView(
                onPlayLive: { coordinator.showLivePlayer(context: $0, services: $1) },
                onPlayRecording: { media, services in
                    Task { await PlaybackLauncher(services: services, coordinator: coordinator).play(
                        ratingKey: media.id,
                        type: media.type,
                    ) }
                },
                onOpenLibrary: { identity in
                    guard let library = libraryStore.library(identity) else { return }
                    coordinator.tab = .library
                    coordinator.libraryPath = NavigationPath([library])
                },
            )
            .unavailableWhenOffline()
        }
    }

    private func libraryDetailTabContent(_ library: Library) -> some View {
        NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.identity))) {
            ServerScopedView(server: library.server) { _ in
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

    /// Every destination is shown with the services of its own server.
    private func destination(for route: MainCoordinator.Route) -> some View {
        ServerScopedView(server: route.server) { services in
            routeContent(route, services: services)
        }
    }

    @ViewBuilder
    private func routeContent(_ route: MainCoordinator.Route, services: MediaServices) -> some View {
        let playbackLauncher = PlaybackLauncher(services: services, coordinator: coordinator)
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: services,
                    resolutionMode: .selectedMedia,
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
                onSelectParentSeries: coordinator.returnToSeries,
                onSelectPerson: { coordinator.showPersonDetail($0, server: services.identity) },
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    services: services,
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
                    services: services,
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
        case let .hubDetail(hub):
            HubDetailView(
                viewModel: HubDetailViewModel(hub: hub, services: services),
                onSelectMedia: coordinator.showMediaDetail,
            )
        case let .personDetail(person, _):
            PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: services),
                onSelectMedia: coordinator.showMediaDetail,
            )
        }
    }
}
