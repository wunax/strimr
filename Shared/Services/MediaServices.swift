import Observation

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
    let playback: any MediaPlaybackService
    let downloads: any MediaDownloadService

    init(
        provider: MediaProvider,
        identity: ServerIdentity,
        capabilities: ProviderCapabilities,
        home: any MediaHomeService,
        library: any MediaLibraryService,
        search: any MediaSearchService,
        artwork: any MediaArtworkService,
        detail: any MediaDetailService,
        playback: any MediaPlaybackService,
        downloads: any MediaDownloadService
    ) {
        self.provider = provider
        self.identity = identity
        self.capabilities = capabilities
        self.home = home
        self.library = library
        self.search = search
        self.artwork = artwork
        self.detail = detail
        self.playback = playback
        self.downloads = downloads
    }
}
