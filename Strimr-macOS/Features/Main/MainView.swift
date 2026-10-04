import SwiftUI

struct MainView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(ServerRegistry.self) private var registry
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(AppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(OfflineCoordinator.self) private var offlineCoordinator
    @Environment(\.scenePhase) private var scenePhase

    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel

    init(homeViewModel: HomeViewModel, libraryViewModel: LibraryViewModel) {
        _homeViewModel = State(initialValue: homeViewModel)
        _libraryViewModel = State(initialValue: libraryViewModel)
    }

    var body: some View {
        @Bindable var appModel = appModel

        NavigationSplitView {
            List(selection: $appModel.selection) {
                Section {
                    sidebarLabel("tabs.home", systemImage: "house.fill", item: .home)

                    if settingsManager.interface.displaySeerrDiscoverTab, seerrStore.isLoggedIn {
                        sidebarLabel("tabs.discover", systemImage: "sparkles", item: .discover)
                    }

                    sidebarLabel("tabs.search", systemImage: "magnifyingglass", item: .search)
                    sidebarLabel("downloads.title", systemImage: "arrow.down.circle.fill", item: .downloads)
                    sidebarLabel("tabs.libraries", systemImage: "rectangle.stack.fill", item: .libraries)
                    sidebarLabel("tabs.favorites", systemImage: "star.fill", item: .favorites)
                    if !registry.liveTVServices.isEmpty, settingsManager.interface.displayLiveTVTab {
                        sidebarLabel("livetv.title", systemImage: "tv", item: .liveTV)
                    }
                }

                if !libraryStore.navigationLibraries.isEmpty {
                    Section("tabs.libraries") {
                        ForEach(libraryStore.navigationLibraries, id: \.identity) { library in
                            Label(library.title, systemImage: library.iconName)
                                .tag(AppModel.SidebarItem.library(library.identity))
                        }
                    }
                }

                Section {
                    if sessionManager.canManageAccounts {
                        sidebarLabel("profiles.title", systemImage: "person.crop.circle", item: .profiles)
                        sidebarLabel("settings.accounts.title", systemImage: "server.rack", item: .accounts)
                    }
                    sidebarLabel("settings.title", systemImage: "gearshape.fill", item: .settings)
                }
            }
            .navigationTitle("Strimr")
            .listStyle(.sidebar)
        } detail: {
            NavigationStack(path: appModel.pathBinding(for: appModel.selection)) {
                rootView(for: appModel.selection)
                    .navigationDestination(for: AppModel.Route.self) { route in
                        destination(for: route)
                    }
            }
            .id(appModel.selection)
            .offlineBanner()
            .animation(.easeInOut, value: offlineCoordinator.banner)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    profileMenu
                }
            }
        }
        .task {
            sharePlayCoordinator.configurePlaybackPresenter(appModel)
            do {
                try await libraryStore.loadLibraries()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
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
                appModel.resetLiveTVNavigation()
            }
        }
        .onChange(of: appModel.playerPresentation?.id) { previous, current in
            // Only the server of the item that was played is reloaded, to update Reprendre and Next Up.
            guard previous != nil, current == nil, let server = lastPlayedServer else { return }
            Task { await homeViewModel.refresh(server: server) }
        }
        .onChange(of: appModel.playerPresentation?.mediaServices?.identity) { _, server in
            if let server {
                lastPlayedServer = server
            }
        }
    }

    @State private var lastPlayedServer: ServerIdentity?

    private func refreshLiveTVAvailability() async {
        await registry.refreshLiveTVAvailability()
        if registry.liveTVServices.isEmpty {
            appModel.resetLiveTVNavigation()
        }
    }

    private func sidebarLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        item: AppModel.SidebarItem,
    ) -> some View {
        Label(title, systemImage: systemImage).tag(item)
    }

    private var profileMenu: some View {
        Menu {
            if sessionManager.profiles.count > 1 {
                Button("common.actions.switchProfile", systemImage: "person.2.circle") {
                    sessionManager.requestProfileSelection()
                }
                .disabled(offlineCoordinator.isFullyOffline)
            }
            if sessionManager.canManageAccounts {
                Button("profiles.title", systemImage: "person.crop.circle") {
                    appModel.selection = .profiles
                }
                Button("settings.accounts.title", systemImage: "server.rack") {
                    appModel.selection = .accounts
                }
            }
        } label: {
            Label(sessionManager.activeProfile?.name ?? "Strimr", systemImage: "person.crop.circle")
        }
        .menuStyle(.button)
    }

    @ViewBuilder
    private func rootView(for item: AppModel.SidebarItem) -> some View {
        switch item {
        case .home:
            HomeView(viewModel: homeViewModel, onSelectMedia: appModel.showMedia)
        case .discover:
            SeerrDiscoverView(
                viewModel: SeerrDiscoverViewModel(store: seerrStore),
                searchViewModel: SeerrSearchViewModel(store: seerrStore),
                onSelectMedia: appModel.showSeerr,
            )
            .unavailableWhenOffline()
        case .search:
            SearchView(
                viewModel: SearchViewModel(sessionManager: sessionManager),
                onSelectMedia: { appModel.showMedia($0.media) },
            )
        case .downloads:
            DownloadsView()
        case .libraries:
            LibraryView(viewModel: libraryViewModel, onSelectMedia: appModel.showMedia)
                .navigationDestination(for: Library.self) { library in
                    ServerScopedView(server: library.server) { _ in
                        LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
                    }
                }
        case .favorites:
            FavoritesView(sessionManager: sessionManager, onSelectMedia: appModel.showMedia)
                .unavailableWhenOffline()
        case .liveTV:
            LiveTVServersView(
                onPlayLive: { appModel.showLivePlayer(context: $0, services: $1) },
                onPlayRecording: { media, services in
                    Task { await PlaybackLauncher(services: services, coordinator: appModel).play(
                        ratingKey: media.id,
                        type: media.type,
                    ) }
                },
                onOpenLibrary: { identity in
                    guard let library = libraryStore.library(identity) else { return }
                    appModel.selection = .libraries
                    appModel.showLibrary(library)
                },
            )
            .unavailableWhenOffline()
        case let .library(identity):
            if let library = libraryStore.library(identity) {
                ServerScopedView(server: library.server) { _ in
                    LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
                }
            } else {
                ContentUnavailableView("library.empty.title", systemImage: "rectangle.stack.fill")
            }
        case .profiles:
            ProfilesSettingsView()
        case .accounts:
            AccountsSettingsView()
        case .settings:
            SettingsView()
        }
    }

    /// Server-bound destinations are shown with the services of their own server.
    @ViewBuilder
    private func destination(for route: AppModel.Route) -> some View {
        if case let .seerr(media) = route {
            SeerrMediaDetailView(
                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                onSelectMedia: appModel.showSeerr,
            )
        } else {
            ServerScopedView(server: route.server) { services in
                routeContent(route, services: services)
            }
        }
    }

    @ViewBuilder
    private func routeContent(_ route: AppModel.Route, services: MediaServices) -> some View {
        let play = { (ratingKey: String, type: MediaKind, shuffle: Bool, shouldResume: Bool) in
            Task {
                await PlaybackLauncher(services: services, coordinator: appModel).play(
                    ratingKey: ratingKey,
                    type: type,
                    shuffle: shuffle,
                    shouldResumeFromOffset: shouldResume,
                )
            }
        }
        switch route {
        case let .media(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: services,
                    resolutionMode: .selectedMedia,
                    copyFinder: MediaCopyFinder(sessionManager: sessionManager),
                    onSelectCopy: appModel.showMedia,
                ),
                onSelectMedia: appModel.showMedia,
                onSelectParentSeries: appModel.returnToSeries,
                onSelectPerson: { appModel.showPerson($0, server: services.identity) },
                onPlay: { ratingKey, type, shuffle, shouldResume in play(ratingKey, type, shuffle, shouldResume) },
            )
        case let .collection(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(collection: collection, services: services),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .collection, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .collection, true, true) },
            )
        case let .playlist(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(playlist: playlist, services: services),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .playlist, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .playlist, true, true) },
            )
        case let .hub(hub):
            HubDetailView(
                viewModel: HubDetailViewModel(hub: hub, services: services),
                onSelectMedia: appModel.showMedia,
            )
        case let .person(person, _):
            PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: services),
                onSelectMedia: appModel.showMedia,
            )
        case let .library(library):
            LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
        case .seerr:
            EmptyView()
        }
    }
}
