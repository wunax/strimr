import Observation

@MainActor
@Observable
final class MediaFocusModel {
    var focusedMedia: MediaItem?

    init(focusedMedia: MediaItem? = nil) {
        self.focusedMedia = focusedMedia
    }
}
