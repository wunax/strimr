import Observation

/// The Explore card in focus, which the hero above the rails describes.
@MainActor
@Observable
final class ExploreFocusModel {
    var focusedItem: ExploreItem?
}
