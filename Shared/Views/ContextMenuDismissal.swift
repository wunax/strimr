import SwiftUI

/// A menu or a dialog keeps animating its dismissal after an item is chosen, and an alert requested meanwhile is
/// dropped for good. Results that arrive sooner wait for it to be gone.
enum ContextMenuDismissal {
    @MainActor
    static func wait(timeout: Duration = .seconds(2)) async {
        #if !os(macOS)
            let deadline = ContinuousClock.now + timeout
            while isDismissing, ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(50))
            }
        #endif
    }

    #if !os(macOS)
        @MainActor
        private static var isDismissing: Bool {
            windows.contains { window in
                window.subviews.contains { String(describing: type(of: $0)).contains("ContextMenu") }
                    || presentedControllers(from: window.rootViewController).contains {
                        $0.isBeingPresented || $0.isBeingDismissed
                    }
            }
        }

        @MainActor
        private static func presentedControllers(from root: UIViewController?) -> [UIViewController] {
            var controllers: [UIViewController] = []
            var current = root?.presentedViewController
            while let controller = current {
                controllers.append(controller)
                current = controller.presentedViewController
            }
            return controllers
        }

        @MainActor
        private static var windows: [UIWindow] {
            UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }.flatMap(\.windows)
        }
    #endif
}
