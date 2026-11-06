import SwiftUI
import UIKit

/// After a back press closes a menu, tvOS keeps focus on the hidden menu item for over a second. Another back press
/// during that time finds nothing to close and leaves the app, so it is consumed here.
struct ClosingMenuBackPressGuard: UIViewRepresentable {
    func makeUIView(context _: Context) -> GuardView {
        GuardView()
    }

    func updateUIView(_: GuardView, context _: Context) {}

    final class GuardView: UIView, UIGestureRecognizerDelegate {
        /// Measured at about 1.2 s. Bounded so that a menu reopened on a reused cell still closes.
        private static let closingDuration: TimeInterval = 2

        private weak var closingMenuItem: AnyObject?
        private var closingDate: Date?

        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer()
            recognizer.allowedPressTypes = [NSNumber(value: UIPress.PressType.menu.rawValue)]
            recognizer.delegate = self
            return recognizer
        }()

        override func didMoveToWindow() {
            super.didMoveToWindow()
            recognizer.view?.removeGestureRecognizer(recognizer)
            window?.addGestureRecognizer(recognizer)
        }

        func gestureRecognizer(_: UIGestureRecognizer, shouldReceive _: UIPress) -> Bool {
            guard let focusedItem = window?.windowScene?.focusSystem?.focusedItem,
                  isMenuItem(focusedItem)
            else { return false }

            if focusedItem === closingMenuItem,
               let closingDate,
               Date().timeIntervalSince(closingDate) < Self.closingDuration
            {
                return true
            }

            closingMenuItem = focusedItem
            closingDate = Date()
            return false
        }

        /// UIKit offers no public way to recognize its menu items. If this name changes, back presses simply behave
        /// as they do without this guard.
        private func isMenuItem(_ item: UIFocusItem) -> Bool {
            String(describing: type(of: item)).hasPrefix("_UIContextMenu")
        }
    }
}
