import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SessionManager.self) var sessionManager
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(MediaServices.self) var mediaServices
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var coordinator = MainCoordinator()
    @State var homeViewModel: HomeViewModel
    @State var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        Group {
            if #available(iOS 18.0, *) {
                modernTabView
            } else {
                legacyTabView
            }
        }
        .environmentObject(coordinator)
        .task {
            try? await libraryStore.loadLibraries()
            sharePlayCoordinator.configurePlaybackLauncher(
                PlaybackLauncher(
                    services: mediaServices,
                    coordinator: coordinator,
                ),
            )
        }
        .task(id: mediaServices.identity) {
            if await mediaServices.liveTVStore.refreshAvailability() == false {
                coordinator.resetLiveTVNavigation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if await mediaServices.liveTVStore.refreshAvailability() == false {
                    coordinator.resetLiveTVNavigation()
                }
            }
        }
        .fullScreenCover(isPresented: $coordinator.isPresentingPlayer, onDismiss: coordinator.resetPlayer) {
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
                .environment(plexApiContext)
            } else if let context = coordinator.selectedLiveTVContext,
                      let services = coordinator.selectedMediaServices
            {
                PlayerWrapper(viewModel: PlayerViewModel(live: context, services: services))
                    .environment(plexApiContext)
            }
        }
    }

    @available(iOS 18.0, *)
    private var modernTabView: some View {
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

            if mediaServices.liveTVStore.isAvailable {
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
                ForEach(navigationLibraries) { library in
                    Tab(
                        library.title,
                        systemImage: library.iconName,
                        value: MainCoordinator.Tab.libraryDetail(library.id),
                    ) {
                        libraryDetailTabContent(library)
                    }
                }
            }
        }
    }

    private var legacyTabView: some View {
        TabView(selection: $coordinator.tab) {
            homeTabContent
                .tabItem {
                    Label("tabs.home", systemImage: "house.fill")
                }
                .tag(MainCoordinator.Tab.home)

            if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                discoverTabContent
                    .tabItem {
                        Label("tabs.discover", systemImage: "sparkles")
                    }
                    .tag(MainCoordinator.Tab.seerrDiscover)
            }

            searchTabContent
                .tabItem {
                    Label("tabs.search", systemImage: "magnifyingglass")
                }
                .tag(MainCoordinator.Tab.search)

            if settingsManager.interface.displayDownloadsTab {
                downloadsTabContent
                    .tabItem {
                        Label("downloads.title", systemImage: "arrow.down.circle.fill")
                    }
                    .tag(MainCoordinator.Tab.downloads)
            }

            libraryTabContent
                .tabItem {
                    Label("tabs.libraries", systemImage: "rectangle.stack.fill")
                }
                .tag(MainCoordinator.Tab.library)

            if mediaServices.liveTVStore.isAvailable {
                liveTVTabContent
                    .tabItem { Label("livetv.title", systemImage: "tv") }
                    .tag(MainCoordinator.Tab.liveTV)
            }

            if settingsManager.interface.displayFavoritesTab {
                favoritesTabContent
                    .tabItem {
                        Label("tabs.favorites", systemImage: "star.fill")
                    }
                    .tag(MainCoordinator.Tab.favorites)
            }

            ForEach(navigationLibraries) { library in
                libraryDetailTabContent(library)
                    .tabItem {
                        Label(library.title, systemImage: library.iconName)
                    }
                    .tag(MainCoordinator.Tab.libraryDetail(library.id))
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
                viewModel: SearchViewModel(
                    services: mediaServices,
                    settingsManager: settingsManager,
                ),
                onSelectMedia: coordinator.showSearchResult,
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

    private var downloadsTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .downloads)) {
            DownloadsView()
        }
    }

    private var favoritesTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .favorites)) {
            FavoritesView(
                services: mediaServices,
                onSelectMedia: coordinator.showMediaDetail,
            )
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    private var liveTVTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .liveTV)) {
            LiveTVView(
                store: mediaServices.liveTVStore,
                onPlayLive: { coordinator.showLivePlayer(context: $0, services: mediaServices) },
                onPlayRecording: { media in
                    Task { await PlaybackLauncher(services: mediaServices, coordinator: coordinator).play(ratingKey: media.id, type: media.type) }
                },
                onOpenLibrary: { libraryID in
                    guard let library = libraryStore.libraries.first(where: { $0.id == libraryID }) else { return }
                    coordinator.tab = .library
                    coordinator.libraryPath = NavigationPath([library])
                },
            )
        }
    }

    private func libraryDetailTabContent(_ library: Library) -> some View {
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

    private var navigationLibraries: [Library] {
        let libraryById = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryById[$0] }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        let routeServices = coordinator.services(for: coordinator.tab, default: mediaServices)
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: routeServices,
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
                onSelectPerson: coordinator.showPersonDetail,
            )
        case let .collectionDetail(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(
                    collection: collection,
                    services: routeServices,
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
                    services: routeServices,
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
                viewModel: HubDetailViewModel(hub: hub, services: routeServices),
                onSelectMedia: coordinator.showMediaDetail,
            )
        case let .personDetail(person):
            PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: routeServices),
                onSelectMedia: coordinator.showMediaDetail,
            )
        }
    }

    private var playbackLauncher: PlaybackLauncher {
        PlaybackLauncher(
            services: coordinator.services(for: coordinator.tab, default: mediaServices),
            coordinator: coordinator,
        )
    }
}
