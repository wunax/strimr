import SwiftUI

/// Retries the writes that failed earlier each time the app comes back to the foreground.
private struct TrackerQueueFlushing: ViewModifier {
    @Environment(\.scenePhase) private var scenePhase

    func body(content: Content) -> some View {
        content.onChange(of: scenePhase) { _, phase in
            if phase == .active {
                TrackerCoordinator.shared.flushQueue()
            }
        }
    }
}

extension View {
    func flushesTrackerQueue() -> some View {
        modifier(TrackerQueueFlushing())
    }
}
