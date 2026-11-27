import SwiftUI
import UIKit
import UIKit.UIGestureRecognizerSubclass

extension View {
    /// Follows the left and right presses of the remote while `isEnabled`: `onPress` as each press starts, before
    /// the focus engine turns it into a move command, and `onHold` once it has been held down.
    func playerArrowHold(
        isEnabled: Bool,
        onPress: @escaping (_ forward: Bool) -> Void,
        onHold: @escaping (_ forward: Bool) -> Void,
    ) -> some View {
        background {
            PlayerArrowHold(isEnabled: isEnabled, onPress: onPress, onHold: onHold)
        }
    }
}

private struct PlayerArrowHold: UIViewRepresentable {
    var isEnabled: Bool
    var onPress: (Bool) -> Void
    var onHold: (Bool) -> Void

    func makeUIView(context _: Context) -> PlayerArrowHoldView {
        PlayerArrowHoldView()
    }

    func updateUIView(_ view: PlayerArrowHoldView, context _: Context) {
        view.recognizer.onPress = onPress
        view.recognizer.onHold = onHold
        view.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: PlayerArrowHoldView, coordinator _: ()) {
        view.recognizer.view?.removeGestureRecognizer(view.recognizer)
    }
}

/// Presses reach the focused view's window, not the SwiftUI view, so the recognizer sits on the window.
final class PlayerArrowHoldView: UIView {
    let recognizer = PlayerArrowHoldRecognizer()

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        recognizer.view?.removeGestureRecognizer(recognizer)
        window?.addGestureRecognizer(recognizer)
    }
}

/// Never recognizes, so the presses still reach the focus engine as move commands.
final class PlayerArrowHoldRecognizer: UIGestureRecognizer, UIGestureRecognizerDelegate {
    var onPress: (Bool) -> Void = { _ in }
    var onHold: (Bool) -> Void = { _ in }

    private static let holdDuration: TimeInterval = 0.45
    private var holdWorkItem: DispatchWorkItem?

    init() {
        super.init(target: nil, action: nil)
        allowedTouchTypes = []
        allowedPressTypes = [
            NSNumber(value: UIPress.PressType.leftArrow.rawValue),
            NSNumber(value: UIPress.PressType.rightArrow.rawValue),
        ]
        cancelsTouchesInView = false
        delaysTouchesEnded = false
        delegate = self
    }

    override func pressesBegan(_ presses: Set<UIPress>, with _: UIPressesEvent) {
        guard let press = presses.first(where: { $0.type == .leftArrow || $0.type == .rightArrow }) else { return }
        let forward = press.type == .rightArrow
        onPress(forward)
        holdWorkItem?.cancel()
        let workItem = DispatchWorkItem { [weak self] in
            self?.onHold(forward)
        }
        holdWorkItem = workItem
        DispatchQueue.main.asyncAfter(deadline: .now() + Self.holdDuration, execute: workItem)
    }

    override func pressesEnded(_: Set<UIPress>, with _: UIPressesEvent) {
        state = .failed
    }

    override func pressesCancelled(_: Set<UIPress>, with _: UIPressesEvent) {
        state = .failed
    }

    override func reset() {
        super.reset()
        holdWorkItem?.cancel()
        holdWorkItem = nil
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}
