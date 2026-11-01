import SwiftUI

/// A menu keeps animating its dismissal for about a second after an item is chosen, and an alert requested meanwhile
/// is dropped for good. Results that arrive sooner wait for the menu to be gone.
enum ContextMenuDismissal {
    @MainActor
    static func wait(timeout: Duration = .seconds(2)) async {
        #if os(iOS)
            let deadline = ContinuousClock.now + timeout
            while isMenuShown, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        #endif
    }

    #if os(iOS)
        @MainActor
        private static var isMenuShown: Bool {
            windows.contains { window in
                window.subviews.contains { String(describing: type(of: $0)).contains("ContextMenu") }
            }
        }

        @MainActor
        private static var windows: [UIWindow] {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        }
    #endif
}
