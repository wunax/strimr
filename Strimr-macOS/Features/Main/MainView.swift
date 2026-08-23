import SwiftUI

struct MainView: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(AppModel.self) private var appModel
    @Environment(SharePlayCoordinator.self) private var sharePlayCoordinator
    @Environment(MediaServices.self) private var mediaServices
    @Environment(\.scenePhase) private var scenePhase

    @State private var homeViewModel: HomeViewModel
    @State private var libraryViewModel: LibraryViewModel
    @State private var isShowingLogoutConfirmation = false

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
                    if mediaServices.liveTVStore.isAvailable {
                        sidebarLabel("livetv.title", systemImage: "tv", item: .liveTV)
                    }
                }

                if !navigationLibraries.isEmpty {
                    Section("tabs.libraries") {
                        ForEach(navigationLibraries) { library in
                            Label(library.title, systemImage: library.iconName)
                                .tag(AppModel.SidebarItem.library(library.id))
                        }
                    }
                }

                Section {
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
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    accountMenu
                }
            }
        }
        .task {
            sharePlayCoordinator.configurePlaybackLauncher(
                PlaybackLauncher(services: mediaServices, coordinator: appModel),
            )
            do {
                try await libraryStore.loadLibraries()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
            }
        }
        .task(id: mediaServices.identity) {
            if await mediaServices.liveTVStore.refreshAvailability() == false {
                appModel.resetLiveTVNavigation()
            }
        }
        .onChange(of: scenePhase) { _, phase in
            guard phase == .active else { return }
            Task {
                if await mediaServices.liveTVStore.refreshAvailability() == false {
                    appModel.resetLiveTVNavigation()
                }
            }
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
    }

    private func sidebarLabel(
        _ title: LocalizedStringKey,
        systemImage: String,
        item: AppModel.SidebarItem,
    ) -> some View {
        Label(title, systemImage: systemImage).tag(item)
    }

    private var accountMenu: some View {
        Menu {
            if sessionManager.mediaServices?.capabilities.profiles == true {
                Button("common.actions.switchProfile", systemImage: "person.2.circle") {
                    Task { await sessionManager.requestProfileSelection() }
                }
            }
            if sessionManager.provider == .plex {
                Button("common.actions.switchServer", systemImage: "server.rack") {
                    Task { await sessionManager.requestServerSelection() }
                }
            }
            Divider()
            Button("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                isShowingLogoutConfirmation = true
            }
        } label: {
            Label(
                sessionManager.user?.friendlyName ?? sessionManager.user?.title ?? "Strimr",
                systemImage: "person.crop.circle",
            )
        }
        .menuStyle(.button)
    }

    private var navigationLibraries: [Library] {
        let libraryByID = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryByID[$0] }
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
        case .search:
            SearchView(
                viewModel: SearchViewModel(
                    services: mediaServices,
                    settingsManager: settingsManager,
                ),
                onSelectMedia: appModel.showSearchResult,
            )
        case .downloads:
            DownloadsView()
        case .libraries:
            LibraryView(viewModel: libraryViewModel, onSelectMedia: appModel.showMedia)
                .navigationDestination(for: Library.self) { library in
                    LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
                }
        case .favorites:
            FavoritesView(services: mediaServices, onSelectMedia: appModel.showMedia)
        case .liveTV:
            LiveTVView(
                store: mediaServices.liveTVStore,
                onPlayLive: { appModel.showLivePlayer(context: $0, services: mediaServices) },
                onPlayRecording: { media in
                    Task { await PlaybackLauncher(services: mediaServices, coordinator: appModel).play(ratingKey: media.id, type: media.type) }
                },
                onOpenLibrary: { libraryID in
                    guard let library = libraryStore.libraries.first(where: { $0.id == libraryID }) else { return }
                    appModel.selection = .libraries
                    appModel.showLibrary(library)
                },
            )
        case let .library(id):
            if let library = libraryStore.libraries.first(where: { $0.id == id }) {
                LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
            } else {
                ContentUnavailableView("library.empty.title", systemImage: "rectangle.stack.fill")
            }
        case .settings:
            SettingsView()
        }
    }

    @ViewBuilder
    private func destination(for route: AppModel.Route) -> some View {
        let routeServices = appModel.services(for: appModel.selection, default: mediaServices)
        switch route {
        case let .media(media):
            MediaDetailView(
                viewModel: MediaDetailViewModel(
                    media: media,
                    services: routeServices,
                    resolutionMode: .selectedMedia,
                ),
                onSelectMedia: appModel.showMedia,
                onSelectParentSeries: appModel.returnToSeries,
                onSelectPerson: appModel.showPerson,
                onPlay: play,
            )
        case let .collection(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(collection: collection, services: routeServices),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .collection, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .collection, true, true) },
            )
        case let .playlist(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(playlist: playlist, services: routeServices),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .playlist, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .playlist, true, true) },
            )
        case let .hub(hub):
            HubDetailView(
                viewModel: HubDetailViewModel(hub: hub, services: routeServices),
                onSelectMedia: appModel.showMedia,
            )
        case let .person(person):
            PersonDetailView(
                viewModel: PersonDetailViewModel(person: person, services: routeServices),
                onSelectMedia: appModel.showMedia,
            )
        case let .library(library):
            LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
        case let .seerr(media):
            SeerrMediaDetailView(
                viewModel: SeerrMediaDetailViewModel(media: media, store: seerrStore),
                onSelectMedia: appModel.showSeerr,
            )
        }
    }

    private func play(
        _ ratingKey: String,
        _ type: MediaKind,
        _ shuffle: Bool = false,
        _ shouldResume: Bool = true,
    ) {
        Task {
            await PlaybackLauncher(
                services: appModel.services(for: appModel.selection, default: mediaServices),
                coordinator: appModel,
            ).play(
                ratingKey: ratingKey,
                type: type,
                shuffle: shuffle,
                shouldResumeFromOffset: shouldResume,
            )
        }
    }
}
