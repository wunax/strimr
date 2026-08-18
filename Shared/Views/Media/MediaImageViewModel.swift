import Foundation
import Observation

@MainActor
@Observable
final class MediaImageViewModel {
    enum ArtworkKind: String {
        case thumb
        case art
    }

    @ObservationIgnored private let service: any MediaArtworkService
    var artworkKind: ArtworkKind
    var media: MediaDisplayItem
    var spoilerProtection = SpoilerProtectionLevel.off
    private(set) var resource: ArtworkResource?

    init(services: MediaServices, artworkKind: ArtworkKind, media: MediaDisplayItem) {
        service = services.artwork
        self.artworkKind = artworkKind
        self.media = media
    }

    func load() async {
        let path: String? = if let item = media.playableItem, item.isSpoilerProtected(at: spoilerProtection) {
            item.spoilerProtectedArtworkPath(at: spoilerProtection)
        } else {
            switch artworkKind {
            case .thumb:
                media.preferredThumbPath
            case .art:
                media.preferredArtPath
            }
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
