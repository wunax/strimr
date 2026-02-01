import Observation

@MainActor
@Observable
final class SeerrFocusModel {
    var focusedMedia: SeerrMedia?

    init(focusedMedia: SeerrMedia? = nil) {
        self.focusedMedia = focusedMedia
    }
}
