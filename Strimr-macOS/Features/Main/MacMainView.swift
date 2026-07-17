import SwiftUI

struct MacMainView: View {
    @Environment(PlexAPIContext.self) private var context
    @Environment(SessionManager.self) private var sessionManager
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SeerrStore.self) private var seerrStore
    @Environment(MacAppModel.self) private var appModel

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
                    sidebarLabel("tabs.libraries", systemImage: "rectangle.stack.fill", item: .libraries)
                }

                if !navigationLibraries.isEmpty {
                    Section("tabs.libraries") {
                        ForEach(navigationLibraries) { library in
                            Label(library.title, systemImage: library.iconName)
                                .tag(MacAppModel.SidebarItem.library(library.id))
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
                    .navigationDestination(for: MacAppModel.Route.self) { route in
                        destination(for: route)
                    }
            }
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    accountMenu
                }
            }
        }
        .task {
            do {
                try await libraryStore.loadLibraries()
            } catch {
                guard !Task.isCancelled, !error.isCancellation else { return }
                ErrorReporter.capture(error)
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
        item: MacAppModel.SidebarItem,
    ) -> some View {
        Label(title, systemImage: systemImage).tag(item)
    }

    private var accountMenu: some View {
        Menu {
            Button("common.actions.switchProfile", systemImage: "person.2.circle") {
                Task { await sessionManager.requestProfileSelection() }
            }
            Button("common.actions.switchServer", systemImage: "server.rack") {
                Task { await sessionManager.requestServerSelection() }
            }
            Divider()
            Button("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                isShowingLogoutConfirmation = true
            }
        } label: {
            Label(sessionManager.user?.friendlyName ?? sessionManager.user?.title ?? "Strimr", systemImage: "person.crop.circle")
        }
        .menuStyle(.button)
    }

    private var navigationLibraries: [Library] {
        let libraryByID = Dictionary(uniqueKeysWithValues: libraryStore.libraries.map { ($0.id, $0) })
        return settingsManager.interface.navigationLibraryIds.compactMap { libraryByID[$0] }
    }

    @ViewBuilder
    private func rootView(for item: MacAppModel.SidebarItem) -> some View {
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
                viewModel: SearchViewModel(context: context),
                onSelectMedia: appModel.showMedia,
            )
        case .libraries:
            LibraryView(viewModel: libraryViewModel, onSelectMedia: appModel.showMedia)
                .navigationDestination(for: Library.self) { library in
                    LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
                }
        case let .library(id):
            if let library = libraryStore.libraries.first(where: { $0.id == id }) {
                LibraryDetailView(library: library, onSelectMedia: appModel.showMedia)
            } else {
                ContentUnavailableView("library.empty.title", systemImage: "rectangle.stack.fill")
            }
        case .settings:
            MacSettingsView()
        }
    }

    @ViewBuilder
    private func destination(for route: MacAppModel.Route) -> some View {
        switch route {
        case let .media(media):
            MacMediaDetailView(
                viewModel: MediaDetailViewModel(media: media, context: context),
                onSelectMedia: appModel.showMedia,
                onPlay: play,
            )
        case let .collection(collection):
            CollectionDetailView(
                viewModel: CollectionDetailViewModel(collection: collection, context: context),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .collection, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .collection, true, true) },
            )
        case let .playlist(playlist):
            PlaylistDetailView(
                viewModel: PlaylistDetailViewModel(playlist: playlist, context: context),
                onSelectMedia: appModel.showMedia,
                onPlay: { ratingKey in play(ratingKey, .playlist, false, true) },
                onShuffle: { ratingKey in play(ratingKey, .playlist, true, true) },
            )
        case let .hub(hub):
            HubDetailView(
                viewModel: HubDetailViewModel(hub: hub, context: context),
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
        _ type: PlexItemType,
        _ shuffle: Bool = false,
        _ shouldResume: Bool = true,
    ) {
        Task {
            await PlaybackLauncher(context: context, coordinator: appModel).play(
                ratingKey: ratingKey,
                type: type,
                shuffle: shuffle,
                shouldResumeFromOffset: shouldResume,
            )
        }
    }
}
