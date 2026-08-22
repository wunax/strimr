import Observation

struct MediaAuthorization: Equatable, Sendable {
    let isAdministrator: Bool
    let canManageSubtitles: Bool
    let canManageServer: Bool

    static let denied = MediaAuthorization(
        isAdministrator: false,
        canManageSubtitles: false,
        canManageServer: false,
    )

    static let plex = MediaAuthorization(
        isAdministrator: false,
        canManageSubtitles: true,
        canManageServer: false,
    )
}

@MainActor
protocol MediaAuthorizationService: AnyObject {
    var authorization: MediaAuthorization { get }
}

@MainActor
@Observable
final class MediaServices {
    let provider: MediaProvider
    let identity: ServerIdentity
    let capabilities: ProviderCapabilities
    let home: any MediaHomeService
    let library: any MediaLibraryService
    let search: any MediaSearchService
    let artwork: any MediaArtworkService
    let detail: any MediaDetailService
    let favorites: any MediaFavoritesService
    let playback: any MediaPlaybackService
    let downloads: any MediaDownloadService
    @ObservationIgnored private let authorizationService: any MediaAuthorizationService

    var authorization: MediaAuthorization {
        authorizationService.authorization
    }

    init(
        provider: MediaProvider,
        identity: ServerIdentity,
        capabilities: ProviderCapabilities,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        favorites: any MediaFavoritesService,
        playback: any MediaPlaybackService,
        downloads: any MediaDownloadService,
        authorization: any MediaAuthorizationService,
    ) {
        self.provider = provider
        self.identity = identity
        self.capabilities = capabilities
        self.home = home
        self.library = library
        self.search = search
        self.artwork = artwork
        self.detail = detail
        self.favorites = favorites
        self.playback = playback
        self.downloads = downloads
        authorizationService = authorization
    }
}
