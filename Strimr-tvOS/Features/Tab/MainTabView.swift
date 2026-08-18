import SwiftUI

struct MainTabView: View {
    @Environment(PlexAPIContext.self) var plexApiContext
    @Environment(SessionManager.self) var sessionManager
    @Environment(SettingsManager.self) var settingsManager
    @Environment(LibraryStore.self) var libraryStore
    @Environment(SeerrStore.self) var seerrStore
    @Environment(SharePlayCoordinator.self) var sharePlayCoordinator
    @Environment(TopShelfDeepLinkRouter.self) var topShelfDeepLinkRouter
    @Environment(MediaServices.self) var mediaServices
    @StateObject var coordinator = MainCoordinator()

    var body: some View {
        TabView(selection: $coordinator.tab) {
            Tab("tabs.home", systemImage: "house.fill", value: MainCoordinator.Tab.home) {
                NavigationStack(path: coordinator.pathBinding(for: .home)) {
                    HomeView(
                        viewModel: HomeViewModel(
                            services: mediaServices,
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
                        viewModel: SearchViewModel(
                            services: mediaServices,
                            settingsManager: settingsManager,
                        ),
                        onSelectMedia: coordinator.showSearchResult,
                    )
                    .navigationDestination(for: MainCoordinator.Route.self) { route in
                        destination(for: route)
                    }
                }
            }

            Tab("tabs.libraries", systemImage: "rectangle.stack.fill", value: MainCoordinator.Tab.library) {
                NavigationStack(path: coordinator.pathBinding(for: .library)) {
                    LibraryView(
                        viewModel: LibraryViewModel(
                            services: mediaServices,
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
                    MoreView()
                        .navigationDestination(for: MoreRoute.self) { route in
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
            sharePlayCoordinator.configurePlaybackLauncher(
                PlaybackLauncher(
                    services: mediaServices,
                    coordinator: coordinator,
                ),
            )
        }
        .task(id: topShelfDeepLinkRouter.pendingAction) {
            guard let action = topShelfDeepLinkRouter.pendingAction else { return }
            defer { topShelfDeepLinkRouter.clear(action) }
            guard action.provider == mediaServices.provider,
                  action.serverIdentifier == nil
                  || action.serverIdentifier == "plex"
                  || action.serverIdentifier == mediaServices.identity.id
            else { return }

            switch action.kind {
            case .display:
                do {
                    let item = try await mediaServices.detail.mediaItem(id: action.ratingKey)
                    coordinator.tab = .home
                    coordinator.showMediaDetail(item)
                } catch {
                    guard !Task.isCancelled, !error.isCancellation else { return }
                    ErrorReporter.capture(error)
                }
            case .play:
                await playbackLauncher.play(ratingKey: action.ratingKey, type: action.type)
            }
        }
        .overlay {
            if coordinator.isPresentingPlayer,
               let queue = coordinator.selectedMediaQueue,
               let services = coordinator.selectedMediaServices
            {
                PlayerWrapper(
                    viewModel: PlayerViewModel(
                        queue: queue,
                        services: services,
                        shouldResumeFromOffset: coordinator.shouldResumeFromOffset,
                    ),
                    onExit: coordinator.resetPlayer,
                )
                .environment(plexApiContext)
            }
        }
    }

    @ViewBuilder
    private func destination(for route: MainCoordinator.Route) -> some View {
        let routeServices = coordinator.services(for: coordinator.tab, default: mediaServices)
        switch route {
        case let .mediaDetail(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(media: media, services: routeServices),
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

    private var navigationLibraries: [Library] {
        let libraryById = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryById[$0] }
    }

    private var playbackLauncher: PlaybackLauncher {
        PlaybackLauncher(
            services: coordinator.services(for: coordinator.tab, default: mediaServices),
            coordinator: coordinator,
        )
    }
}
