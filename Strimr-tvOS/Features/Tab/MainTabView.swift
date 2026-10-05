import SwiftUI

struct MainTabView: View {
    @Environment(SessionManager.self) var sessionManager
    @Environment(ServerRegistry.self) var registry
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(TopShelfDeepLinkRouter.self) var topShelfDeepLinkRouter
    @Environment(\.scenePhase) private var scenePhase
    @StateObject var coordinator = MainCoordinator()
    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel

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
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                Tab("tabs.discover", systemImage: "sparkles", value: MainCoordinator.Tab.seerrDiscover) {
                    NavigationStack(path: coordinator.pathBinding(for: .seerrDiscover)) {
                        SeerrDiscoverView(
                            viewModel: SeerrDiscoverViewModel(store: seerrStore),
                            onSelectMedia: coordinator.showSeerrMediaDetail,
                        )
                        .navigationDestination(for: SeerrMedia.self) { media in
                            SeerrMediaDetailView(
                                viewModel: SeerrMediaDetailViewModel(
                                    media: media,
                                    store: seerrStore,
                                ),
                            )
                        }
                    }
                }
            }

            Tab("tabs.search", systemImage: "magnifyingglass", value: MainCoordinator.Tab.search, role: .search) {
                NavigationStack(path: coordinator.pathBinding(for: .search)) {
                    SearchView(
                        viewModel: SearchViewModel(sessionManager: sessionManager),
                        onSelectMedia: { coordinator.showMediaDetail($0.media) },
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
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
                        ServerScopedView(server: library.server) { _ in
                            LibraryDetailView(
                                library: library,
                                onSelectMedia: coordinator.showMediaDetail,
                            )
                        }
                    }
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            if !registry.liveTVServices.isEmpty, settingsManager.interface.displayLiveTVTab {
                Tab("livetv.title", systemImage: "tv", value: MainCoordinator.Tab.liveTV) {
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
                    }
                }
            }

            if settingsManager.interface.displayFavoritesTab {
                Tab("tabs.favorites", systemImage: "star.fill", value: MainCoordinator.Tab.favorites) {
                    NavigationStack(path: coordinator.pathBinding(for: .favorites)) {
                        FavoritesView(
                            sessionManager: sessionManager,
                            onSelectMedia: coordinator.showMediaDetail,
                        )
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                    }
                }
            }

            ForEach(libraryStore.navigationLibraries, id: \.identity) { library in
                Tab(
                    library.title,
                    systemImage: library.iconName,
                    value: MainCoordinator.Tab.libraryDetail(library.identity),
                ) {
                    NavigationStack(path: coordinator.pathBinding(for: .libraryDetail(library.identity))) {
                        ServerScopedView(server: library.server) { _ in
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
            }

            Tab("tabs.more", systemImage: "ellipsis.circle", value: MainCoordinator.Tab.more) {
                NavigationStack(path: coordinator.pathBinding(for: .more)) {
                    MoreView()
                        .navigationDestination(for: MoreRoute.self) { route in
                            switch route {
                            case .settings:
                                SettingsView()
                            case .favorites:
                                FavoritesView(
                                    sessionManager: sessionManager,
                                    onSelectMedia: coordinator.showMediaDetail,
                                )
                            }
                        }
                        .navigationDestination(for: MainCoordinator.Route.self) { route in
                            destination(for: route)
                        }
                }
            }
        }
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
        .task(id: topShelfDeepLinkRouter.pendingAction) {
            guard let action = topShelfDeepLinkRouter.pendingAction else { return }
            defer { topShelfDeepLinkRouter.clear(action) }
            // A link to a server outside the active profile is ignored.
            guard let serverIdentifier = action.serverIdentifier,
                  let services = registry.services(for: ServerIdentity(provider: action.provider, id: serverIdentifier))
            else { return }

            switch action.kind {
            case .display:
                do {
                    let item = try await services.detail.mediaItem(id: action.ratingKey)
                    coordinator.tab = .home
                    coordinator.showMediaDetail(item)
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    ErrorReporter.capture(error)
                }
            case .play:
                await PlaybackLauncher(services: services, coordinator: coordinator)
                    .play(ratingKey: action.ratingKey, type: action.type)
            }
        }
        .overlay {
            if coordinator.isPresentingPlayer,
               let services = coordinator.selectedMediaServices
            {
                if let queue = coordinator.selectedMediaQueue {
                    PlayerWrapper(
                        viewModel: PlayerViewModel(
                            queue: queue,
                            services: services,
                            shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                        ),
                        onExit: playerDidClose,
                    )
                    .environment(services)
                } else if let context = coordinator.selectedLiveTVContext {
                    PlayerWrapper(
                        viewModel: PlayerViewModel(live: context, services: services),
                        onExit: coordinator.resetPlayer,
                    )
                    .environment(services)
                }
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

    /// Every destination is shown with the services of its own server.
    private func destination(for route: MainCoordinator.Route) -> some View {
        ServerScopedView(server: route.server) { services in
            routeContent(route, services: services)
        }
    }

    @ViewBuilder
    private func routeContent(_ route: MainCoordinator.Route, services: MediaServices) -> some View {
        let playbackLauncher = PlaybackLauncher(services: services, coordinator: coordinator)
        let routeServices = services
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: routeServices,
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
                onSelectPerson: { coordinator.showPersonDetail($0, server: services.identity) },
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
        case let .personDetail(person, _):
            PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: routeServices),
                onSelectMedia: coordinator.showMediaDetail,
            )
        }
    }
}
