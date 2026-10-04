import Foundation
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
    let serverName: String
    let capabilities: ProviderCapabilities
    let home: any MediaHomeService
    let library: any MediaLibraryService
    let search: any MediaSearchService
    let artwork: any MediaArtworkService
    let detail: any MediaDetailService
    let favorites: any MediaFavoritesService
    let playback: any MediaPlaybackService
    let liveTV: any MediaLiveTVService
    let liveTVStore: LiveTVStore
    let downloads: any MediaDownloadService
    let trackSelectionCoordinator: TrackSelectionCoordinator?
    let trackSelectionAccountIdentifier: String?
    @ObservationIgnored let versionSelectionStore: MediaVersionSelectionStore?
    @ObservationIgnored private let authorizationService: any MediaAuthorizationService
    /// URL of an unauthenticated endpoint used to probe the server's reachability.
    @ObservationIgnored var availabilityProbeURL: (() -> URL?)?

    var authorization: MediaAuthorization {
        authorizationService.authorization
    }

    /// Scope of per-server preferences such as library browsing. A profile has one link per server, so the server and
    /// its user identify the profile's preferences for that server.
    var serverPreferencesScopeID: String {
        [
            identity.provider.rawValue,
            identity.id,
            trackSelectionAccountIdentifier ?? "default",
        ].joined(separator: "|")
    }

    init(
        provider: MediaProvider,
        identity: ServerIdentity,
        serverName: String,
        capabilities: ProviderCapabilities,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        favorites: any MediaFavoritesService,
        playback: any MediaPlaybackService,
        liveTV: any MediaLiveTVService,
        downloads: any MediaDownloadService,
        authorization: any MediaAuthorizationService,
        trackSelectionCoordinator: TrackSelectionCoordinator? = nil,
        trackSelectionAccountIdentifier: String? = nil,
        versionSelectionStore: MediaVersionSelectionStore? = nil,
    ) {
        self.provider = provider
        self.identity = identity
        self.serverName = serverName
        self.capabilities = capabilities
        self.home = home
        self.library = library
        self.search = search
        self.artwork = artwork
        self.detail = detail
        self.favorites = favorites
        self.playback = playback
        self.liveTV = liveTV
        liveTVStore = LiveTVStore(service: liveTV)
        self.downloads = downloads
        self.trackSelectionCoordinator = trackSelectionCoordinator
        self.trackSelectionAccountIdentifier = trackSelectionAccountIdentifier
        self.versionSelectionStore = versionSelectionStore
        authorizationService = authorization
    }
}
