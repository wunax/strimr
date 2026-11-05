import SwiftUI

struct MainTabView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(ServerRegistry.self) var registry
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @StateObject var coordinator: MainCoordinator
    @State var homeViewModel: HomeViewModel
    @State var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel, settingsManager: SettingsManager) {
        _coordinator = StateObject(wrappedValue: MainCoordinator(settingsManager: settingsManager))
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        tabView
            .environmentObject(coordinator)
            .mediaCardActions(registry: registry, presenter: coordinator, showMedia: coordinator.showMediaDetail)
            .onChange(of: tabLayout, initial: true) { _, layout in
                coordinator.updateTabLayout(layout)
            }
            .task {
                sharePlayCoordinator.configurePlaybackPresenter(coordinator)
                try? await libraryStore.loadLibraries()
            }
            .task(id: registry.readyServers) {
                await homeViewModel.syncServers()
                await libraryViewModel.syncServers()
                await refreshLiveTVAvailability()
                #if DEBUG
                    await DemoRoute.apply(coordinator: coordinator, registry: registry)
                #endif
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active else { return }
                Task { await refreshLiveTVAvailability() }
            }
            .handlesExternalPlaybackCallbacks { server in
                Task { await homeViewModel.refresh(server: server) }
            }
            .onChange(of: isDiscoverAvailable, initial: true) { _, isAvailable in
                if isAvailable {
                    coordinator.openPendingStartupTab(.seerrDiscover)
                }
            }
            .onChange(of: isLiveTVAvailable, initial: true) { _, isAvailable in
                if isAvailable {
                    coordinator.openPendingStartupTab(.liveTV)
                }
            }
            .onChange(of: settingsManager.interface.displayLiveTVTab) { _, isDisplayed in
                if !isDisplayed {
                    coordinator.resetLiveTVNavigation()
                }
            }
            .onChange(of: coordinator.isPresentingPlayer, initial: true) { _, isPresenting in
                homeViewModel.isPlaybackActive = isPresenting
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
                            launchNotice: coordinator.playerNotice,
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

    private var isDiscoverAvailable: Bool {
        settingsManager.interface.displaySeerrDiscoverTab && seerrStore.isLoggedIn
    }

    private var isLiveTVAvailable: Bool {
        !registry.liveTVServices.isEmpty && settingsManager.interface.displayLiveTVTab
    }

    private var orderedTabs: [MainCoordinator.Tab] {
        var tabs: [MainCoordinator.Tab] = [.home]
        if isDiscoverAvailable {
            tabs.append(.seerrDiscover)
        }
        if settingsManager.interface.displayDownloadsTab {
            tabs.append(.downloads)
        }
        tabs.append(.library)
        if isLiveTVAvailable {
            tabs.append(.liveTV)
        }
        if settingsManager.interface.displayFavoritesTab {
            tabs.append(.favorites)
        }
        tabs += libraryStore.navigationLibraries.map { .libraryDetail($0.identity) }
        return tabs
    }

    /// Both size classes count: a large iPhone in landscape is regular in width but keeps a compact tab bar.
    private var tabLayout: MainTabLayout {
        MainTabLayout(
            tabs: orderedTabs,
            isCompact: horizontalSizeClass == .compact || verticalSizeClass == .compact,
        )
    }

    private var tabView: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                homeTabContent
            }

            if tabLayout.bar.contains(.seerrDiscover) {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    discoverTabContent
                }
            }

            // On iOS 27, a search-role tab sits in the bar like any tab and, once the bar overflows into More, tapping
            // a tab crashes UIKit; the prominent role keeps it as the separate button.
            if #available(iOS 27.0, *) {
                Tab(
                    "tabs.search",
                    systemImage: "magnifyingglass",
                    value: MainCoordinator.Tab.search,
                    role: .prominent,
                ) {
                    searchTabContent
                }
            } else {
                Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                    searchTabContent
                }
            }

            if tabLayout.bar.contains(.downloads) {
                Tab(value: MainCoordinator.Tab.downloads) {
                    downloadsTabContent
                } label: {
                    tabLabel(.downloads)
                }
            }

            if tabLayout.bar.contains(.library) {
                Tab(value: MainCoordinator.Tab.library) {
                    libraryTabContent
                } label: {
                    tabLabel(.library)
                }
            }

            if tabLayout.bar.contains(.liveTV) {
                Tab(value: MainCoordinator.Tab.liveTV) {
                    liveTVTabContent
                } label: {
                    tabLabel(.liveTV)
                }
            }

            if tabLayout.bar.contains(.favorites) {
                Tab(value: MainCoordinator.Tab.favorites) {
                    favoritesTabContent
                } label: {
                    tabLabel(.favorites)
                }
            }

            TabSection {
                ForEach(libraryStore.navigationLibraries.filter {
                    tabLayout.bar.contains(.libraryDetail($0.identity))
                }, id: \.identity) { library in
                    Tab(value: MainCoordinator.Tab.libraryDetail(library.identity)) {
                        libraryDetailTabContent(library)
                    } label: {
                        tabLabel(.libraryDetail(library.identity))
                    }
                }
            }

            if !tabLayout.overflow.isEmpty {
                Tab("tabs.overflow", systemImage: "ellipsis", value: MainCoordinator.Tab.more) {
                    moreTabContent
                }
            }
        }
    }

    /// Home and Discover come first, so they always stay in the bar.
    @ViewBuilder
    private func tabLabel(_ tab: MainCoordinator.Tab) -> some View {
        switch tab {
        case .downloads:
            Label("downloads.title", systemImage: "arrow.down.circle.fill")
        case .library:
            Label("tabs.libraries", systemImage: "rectangle.stack.fill")
        case .liveTV:
            Label("livetv.title", systemImage: "tv")
        case .favorites:
            Label("tabs.favorites", systemImage: "star.fill")
        case let .libraryDetail(identity):
            if let library = libraryStore.library(identity) {
                Label(library.title, systemImage: library.iconName)
            }
        case .home, .seerrDiscover, .search, .more:
            EmptyView()
        }
    }

    private var moreTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .more)) {
            List(tabLayout.overflow, id: \.self) { tab in
                NavigationLink(value: tab) {
                    tabLabel(tab)
                }
            }
            .navigationTitle("tabs.overflow")
            .tabRootChrome()
            .navigationDestination(for: MainCoordinator.Tab.self) { tab in
                overflowTabRoot(tab)
                    .onAppear { coordinator.moreRootTab = tab }
            }
            .navigationDestination(for: Library.self) {
                libraryDetailRoot($0)
            }
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    @ViewBuilder
    private func overflowTabRoot(_ tab: MainCoordinator.Tab) -> some View {
        switch tab {
        case .downloads:
            DownloadsView()
        case .library:
            libraryRoot
        case .liveTV:
            liveTVRoot
        case .favorites:
            favoritesRoot
        case let .libraryDetail(identity):
            if let library = libraryStore.library(identity) {
                libraryDetailRoot(library)
            }
        case .home, .seerrDiscover, .search, .more:
            EmptyView()
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
                onShowRequests: coordinator.showSeerrRequests,
            )
            .unavailableWhenOffline()
            .navigationDestination(for: SeerrMedia.self) { media in
                SeerrMediaDetailView(
                    viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                    onSelectMedia: coordinator.showSeerrMediaDetail,
                )
            }
            .navigationDestination(for: SeerrRequestsRoute.self) { _ in
                SeerrRequestsView(
                    viewModel: SeerrRequestsViewModel(store: seerrStore),
                    onSelectMedia: coordinator.showSeerrMediaDetail,
                )
            }
        }
    }

    private var searchTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .search)) {
            SearchView(
                viewModel: SearchViewModel(sessionManager: sessionManager, settingsManager: settingsManager),
                onSelectMedia: { coordinator.showMediaDetail($0.media) },
            )
            .navigationDestination(for: MainCoordinator.Route.self) {
                destination(for: $0)
            }
        }
    }

    private var libraryTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .library)) {
            libraryRoot
                .navigationDestination(for: Library.self) {
                    libraryDetailRoot($0)
                }
                .navigationDestination(for: MainCoordinator.Route.self) {
                    destination(for: $0)
                }
        }
    }

    private var libraryRoot: some View {
        LibraryView(
            viewModel: libraryViewModel,
            onSelectMedia: coordinator.showMediaDetail,
        )
    }

    private var downloadsTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .downloads)) {
            DownloadsView()
        }
    }

    private var favoritesTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .favorites)) {
            favoritesRoot
                .navigationDestination(for: MainCoordinator.Route.self) {
                    destination(for: $0)
                }
        }
    }

    private var favoritesRoot: some View {
        FavoritesView(
            sessionManager: sessionManager,
            onSelectMedia: coordinator.showMediaDetail,
        )
        .unavailableWhenOffline()
    }

    private var liveTVTabContent: some View {
        NavigationStack(path: coordinator.pathBinding(for: .liveTV)) {
            liveTVRoot
        }
    }

    private var liveTVRoot: some View {
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
                coordinator.showLibrary(library)
            },
        )
        .unavailableWhenOffline()
    }

    private func libraryDetailTabContent(_ library: Library) -> some View {
        NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.identity))) {
            libraryDetailRoot(library)
                .navigationDestination(for: MainCoordinator.Route.self) {
                    destination(for: $0)
                }
        }
    }

    private func libraryDetailRoot(_ library: Library) -> some View {
        ServerScopedView(server: library.server) { _ in
            LibraryDetailView(
                library: library,
                onSelectMedia: coordinator.showMediaDetail,
            )
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
                    copyFinder: MediaCopyFinder(sessionManager: sessionManager),
                    onSelectCopy: coordinator.showMediaDetail,
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
                onPlayEntry: { entry in
                    Task {
                        await playbackLauncher.playPlaylist(id: playlist.id, startingWith: entry)
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
