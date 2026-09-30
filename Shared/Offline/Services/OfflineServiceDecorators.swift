import Foundation

/// Wraps provider services with the offline cache. Only used on platforms with downloads; tvOS keeps the raw services.
@MainActor
struct OfflineServiceDecorators {
    let home: any MediaHomeService
    let library: any MediaLibraryService
    let search: any MediaSearchService
    let artwork: any MediaArtworkService
    let detail: any MediaDetailService
    let favorites: any MediaFavoritesService

    init(
        owner: MediaOwner,
        serverName: String,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        favorites: any MediaFavoritesService,
    ) {
        guard let store = OfflineCoordinator.shared.store else {
            self.home = home
            self.library = library
            self.search = search
            self.artwork = artwork
            self.detail = detail
            self.favorites = favorites
            return
        }
        let policy = OfflineCachePolicy(owner: owner, store: store, coordinator: .shared)
        self.home = CachedHomeService(base: home, policy: policy)
        self.library = if let plexLibrary = library as? any MediaLibraryService & PlexAdvancedLibraryService {
            CachedPlexLibraryService(base: plexLibrary, policy: policy)
        } else if let browseLibrary = library as? any MediaLibraryService & AdvancedLibraryBrowseService {
            CachedJellyfinLibraryService(base: browseLibrary, policy: policy)
        } else {
            CachedLibraryService(base: library, policy: policy)
        }
        self.search = CachedSearchService(base: search, policy: policy, serverName: serverName)
        self.artwork = CachedArtworkService(base: artwork, owner: owner, store: store, coordinator: .shared)
        self.detail = CachedDetailService(base: detail, policy: policy)
        self.favorites = CachedFavoritesService(base: favorites, policy: policy)
    }

    /// Search results reference their services, which only exist once the decorators are assembled.
    func attach(to services: MediaServices) {
        (search as? CachedSearchService)?.services = services
    }
}
