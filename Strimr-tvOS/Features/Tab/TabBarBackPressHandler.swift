import SwiftUI
import UIKit

/// A back press from the tab bar, or with nothing focused, leaves the app even when the tab has pushed pages. Pages
/// with nothing to focus end up in one of these states, which left no way back to the previous page.
struct TabBarBackPressHandler: UIViewRepresentable {
    let canGoBack: () -> Bool
    let goBack: () -> Void

    func makeUIView(context _: Context) -> HandlerView {
        HandlerView()
    }

    func updateUIView(_ view: HandlerView, context _: Context) {
        view.canGoBack = canGoBack
        view.goBack = goBack
    }

    final class HandlerView: UIView, UIGestureRecognizerDelegate {
        var canGoBack: () -> Bool = { false }
        var goBack: () -> Void = {}

        private lazy var recognizer: UITapGestureRecognizer = {
            let recognizer = UITapGestureRecognizer(target: self, action: #selector(handlePress))
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
            isFocusOutsidePage && window?.rootViewController?.presentedViewController == nil && canGoBack()
        }

        @objc private func handlePress() {
            goBack()
        }

        /// The top bar takes the focus of such pages, while the sidebar stays closed and leaves focus empty.
        private var isFocusOutsidePage: Bool {
            guard let focusedItem = window?.windowScene?.focusSystem?.focusedItem else { return true }
            guard let focusedView = focusedItem as? UIView else { return false }
            return sequence(first: focusedView, next: \.superview).contains { $0 is UITabBar }
        }
    }
}
