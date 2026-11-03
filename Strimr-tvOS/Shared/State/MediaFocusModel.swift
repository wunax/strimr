import Observation

@MainActor
@Observable
final class MediaFocusModel {
    var focusedMedia: MediaItem?
    /// Bumped as soon as a card takes focus, before the hero settles on it, for views that react to focus entering
    /// the cards.
    private(set) var cardFocusCount = 0
    @ObservationIgnored private var pendingUpdate: Task<Void, Never>?

    init(focusedMedia: MediaItem? = nil) {
        self.focusedMedia = focusedMedia
    }

    /// Points the hero at `media` once focus has rested on it.
    func focus(_ media: MediaItem) {
        cardFocusCount += 1
        settle { [weak self] in
            self?.focusedMedia = media
        }
    }

    /// Runs `update` after `Motion.heroFocusDelay` unless focus moves again first, so sweeping along a row neither
    /// chains hero fades nor starts a 4K backdrop load for every card passed. Card focus itself stays immediate.
    func settle(_ update: @escaping @MainActor () -> Void) {
        pendingUpdate?.cancel()
        pendingUpdate = Task {
            try? await Task.sleep(for: Motion.heroFocusDelay)
            guard !Task.isCancelled else { return }
            update()
        }
    }
}
