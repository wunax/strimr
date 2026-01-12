import Foundation
import Observation

@MainActor
@Observable
final class MediaImageViewModel {
    enum ArtworkKind: String {
        case thumb
        case art
    }

    @ObservationIgnored private let context: PlexAPIContext
    var artworkKind: ArtworkKind
    var media: MediaItem
    private(set) var imageURL: URL?

    init(context: PlexAPIContext, artworkKind: ArtworkKind, media: MediaItem) {
        self.context = context
        self.artworkKind = artworkKind
        self.media = media
    }

    func load() async {
        let path: String? = switch artworkKind {
        case .thumb:
            media.grandparentThumbPath ?? media.parentThumbPath ?? media.thumbPath
        case .art:
            media.grandparentArtPath ?? media.artPath
        }

        guard let path else {
            imageURL = nil
            return
        }

        do {
            let imageRepository = try ImageRepository(context: context)
            imageURL = imageRepository.transcodeImageURL(path: path)
        } catch {
            imageURL = nil
        }
    }
}
