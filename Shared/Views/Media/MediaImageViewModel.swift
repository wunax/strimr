import Foundation
import Observation

@MainActor
@Observable
final class MediaImageViewModel {
    enum ArtworkKind: String {
        case thumb
        case art
        /// Card artwork, which follows the series artwork preferences.
        case cardThumb
        case cardArt
    }

    @ObservationIgnored private let service: any MediaArtworkService
    var artworkKind: ArtworkKind
    var media: MediaDisplayItem
    var spoilerProtection = SpoilerProtectionLevel.off
    var landscapeEpisodeArtwork = LandscapeEpisodeArtwork.episode
    var portraitEpisodeArtwork = PortraitEpisodeArtwork.series
    private(set) var resource: ArtworkResource?

    init(services: MediaServices, artworkKind: ArtworkKind, media: MediaDisplayItem) {
        service = services.artwork
        self.artworkKind = artworkKind
        self.media = media
    }

    /// Whether the series artwork preferences replace the default artwork of an episode or season card.
    func followsSeriesArtworkPreference(
        landscape: LandscapeEpisodeArtwork,
        portrait: PortraitEpisodeArtwork,
    ) -> Bool {
        switch (artworkKind, media.type) {
        case (.cardArt, .episode):
            landscape == .series
        case (.cardThumb, .episode), (.cardThumb, .season):
            portrait == .season
        default:
            false
        }
    }

    /// Only the episode's own images can reveal anything, so a series or season poster is never hidden.
    func hidesSpoiler(
        at level: SpoilerProtectionLevel,
        landscape: LandscapeEpisodeArtwork,
        portrait: PortraitEpisodeArtwork,
    ) -> Bool {
        guard let item = media.playableItem,
              item.isSpoilerProtected(at: level),
              !followsSeriesArtworkPreference(landscape: landscape, portrait: portrait)
        else { return false }
        return [item.thumbPath, item.artPath].contains(defaultArtworkPath)
    }

    private var defaultArtworkPath: String? {
        switch artworkKind {
        case .thumb, .cardThumb:
            media.preferredThumbPath
        case .art, .cardArt:
            media.preferredArtPath
        }
    }

    func load() async {
        let path: String? = if let item = media.playableItem,
                               followsSeriesArtworkPreference(
                                   landscape: landscapeEpisodeArtwork,
                                   portrait: portraitEpisodeArtwork,
                               )
        {
            switch (artworkKind, item.type) {
            case (.cardArt, _):
                item.seriesArtworkPath
            case (_, .season):
                item.thumbPath ?? item.preferredThumbPath
            default:
                item.seasonPosterPath
            }
        } else if let item = media.playableItem, hidesSpoiler(
            at: spoilerProtection,
            landscape: landscapeEpisodeArtwork,
            portrait: portraitEpisodeArtwork,
        ) {
            item.spoilerProtectedArtworkPath(at: spoilerProtection)
        } else {
            defaultArtworkPath
        }

        guard let path else {
            resource = nil
            return
        }

        do {
            resource = try await service.artwork(path: path, width: nil, height: nil)
        } catch {
            resource = nil
        }
    }
}
