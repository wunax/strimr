import Foundation
import Observation

@MainActor
@Observable
final class SeerrMediaDetailViewModel {
    let media: SeerrMedia

    init(media: SeerrMedia) {
        self.media = media
    }
}
