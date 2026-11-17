import SwiftUI
import UIKit

extension View {
    /// Remote input of a focusable playback timeline: presses step through the video, a swipe on the touch surface
    /// drags the playhead, a click commits the previewed position, Back cancels it and focus leaving commits it.
    /// The caller binds the focus with `focused(_:)` after this modifier, which makes the view focusable.
    func playerScrubInteraction(
        position: Binding<Double>,
        upperBound: Double,
        stepSize: Double,
        isFocused: Bool,
        pressesScrub: Bool = true,
        swipesScrub: Bool = true,
        onEditingChanged: @escaping (Bool) -> Void,
        onCancel: @escaping () -> Void,
        onIdleMove: ((MoveCommandDirection) -> Void)? = nil,
        onIdleSelect: (() -> Void)? = nil,
        onClickCommit: (() -> Void)? = nil,
        onIdleSwipe: (() -> Void)? = nil,
    ) -> some View {
        modifier(PlayerScrubInteraction(
            position: position,
            upperBound: upperBound,
            stepSize: stepSize,
            isFocused: isFocused,
            pressesScrub: pressesScrub,
            swipesScrub: swipesScrub,
            onEditingChanged: onEditingChanged,
            onCancel: onCancel,
            onIdleMove: onIdleMove,
            onIdleSelect: onIdleSelect,
            onClickCommit: onClickCommit,
            onIdleSwipe: onIdleSwipe,
        ))
    }
}

private struct PlayerScrubInteraction: ViewModifier {
    @Binding var position: Double
    var upperBound: Double
    var stepSize: Double
    var isFocused: Bool
    /// When false, left and right presses go to `onIdleMove` until a swipe has started a scrub.
    var pressesScrub: Bool
    /// When false, the touch surface does nothing until a press has started a scrub.
    var swipesScrub: Bool
    var onEditingChanged: (Bool) -> Void
    var onCancel: () -> Void
    var onIdleMove: ((MoveCommandDirection) -> Void)?
    var onIdleSelect: (() -> Void)?
    /// Called after a click committed a scrub, unlike focus leaving the timeline.
    var onClickCommit: (() -> Void)?
    /// Called when a swipe that does not scrub starts and ends, so it still keeps the controls on screen.
    var onIdleSwipe: (() -> Void)?

    @State private var session = PlayerScrubSession()
    @State private var panStartPosition: Double?
    @State private var lastPanEnd: Date?
    @State private var isSwiping = false
    /// The finger usually still rests on the surface when the click commits, so the rest of that swipe must not
    /// start a new scrub.
    @State private var ignoresCurrentSwipe = false

    /// Share of the video a swipe across the whole touch surface covers.
    private let swipeSpan = 0.06
    /// A swipe can also reach the focus engine as a move command, which would add a step to the drag or, outside a
    /// scrub, seek by 10 seconds where the system player does nothing.
    private let movesIgnoredAfterSwipe: TimeInterval = 0.3

    func body(content: Content) -> some View {
        // A button rather than a tap gesture: the tap fails when the finger moves on the clickpad while it clicks,
        // which happens most right after a swipe.
        Button(action: handleSelect) { content }
            .buttonStyle(PlayerScrubButtonStyle())
            .background {
                PlayerTouchSurfacePan(
                    // Stays on when swipes do not scrub, to tell their move commands from clickpad presses.
                    isEnabled: isFocused,
                    onChanged: handlePan(translation:width:),
                    onEnded: endPan,
                )
            }
            .onMoveCommand(perform: handleMove)
            .onExitCommand(perform: exitAction)
            .onChange(of: isFocused) { _, focused in
                if !focused {
                    commit()
                }
            }
            // The timeline goes away without losing the focus when a prompt or the zoom bar hides the controls;
            // the scrub was not the user's choice to commit then.
            .onDisappear(perform: cancel)
    }

    /// Back only belongs to the timeline during a scrub; otherwise it reaches the player.
    private var exitAction: (() -> Void)? {
        guard session.isActive else { return nil }
        return { cancel() }
    }

    private func handleMove(_ direction: MoveCommandDirection) {
        guard isFocused, direction == .left || direction == .right else { return }
        if isSwiping {
            return
        }
        if let lastPanEnd, Date().timeIntervalSince(lastPanEnd) < movesIgnoredAfterSwipe {
            return
        }
        guard session.isActive || pressesScrub else {
            onIdleMove?(direction)
            return
        }
        if session.begin(at: position) {
            onEditingChanged(true)
        }
        position = session.step(
            from: position,
            forward: direction == .right,
            stepSize: stepSize,
            upperBound: upperBound,
        )
    }

    /// A click on a menu button can end on the timeline while focus moves into the menu, so only a click the
    /// timeline holds the focus for counts.
    private func handleSelect() {
        guard isFocused else { return }
        if session.isActive {
            commit()
            onClickCommit?()
        } else {
            onIdleSelect?()
        }
    }

    private func handlePan(translation: CGFloat, width: CGFloat) {
        guard isFocused, upperBound > 0, width > 0 else { return }
        let isStart = !isSwiping
        isSwiping = true
        guard !ignoresCurrentSwipe, swipesScrub || session.isActive else {
            if isStart {
                onIdleSwipe?()
            }
            return
        }
        if panStartPosition == nil {
            panStartPosition = position
            if session.begin(at: position) {
                onEditingChanged(true)
            }
        }
        guard let panStartPosition else { return }
        let offset = Double(translation / width) * upperBound * swipeSpan
        position = min(max(panStartPosition + offset, 0), upperBound)
    }

    /// The playhead stays where the swipe left it, previewing, until a click commits it.
    private func endPan() {
        guard isSwiping else { return }
        if panStartPosition == nil {
            onIdleSwipe?()
        }
        isSwiping = false
        ignoresCurrentSwipe = false
        panStartPosition = nil
        lastPanEnd = Date()
    }

    private func commit() {
        ignoresCurrentSwipe = isSwiping
        panStartPosition = nil
        if session.commit() {
            onEditingChanged(false)
        }
    }

    private func cancel() {
        ignoresCurrentSwipe = isSwiping
        panStartPosition = nil
        if session.cancel() != nil {
            onCancel()
        }
    }
}

/// Leaves the timeline to draw its own focus, without the system lift and highlight.
private struct PlayerScrubButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
    }
}

/// Follows a finger on the Siri Remote touch surface while the timeline holds the focus. Touches reach the focused
/// view's window, not the SwiftUI view, so the recognizer sits on the window. Clickpad presses stay move commands.
private struct PlayerTouchSurfacePan: UIViewRepresentable {
    var isEnabled: Bool
    var onChanged: (CGFloat, CGFloat) -> Void
    var onEnded: () -> Void

    func makeUIView(context _: Context) -> PlayerTouchSurfacePanView {
        PlayerTouchSurfacePanView()
    }

    func updateUIView(_ view: PlayerTouchSurfacePanView, context _: Context) {
        view.onChanged = onChanged
        view.onEnded = onEnded
        view.recognizer.isEnabled = isEnabled
    }

    static func dismantleUIView(_ view: PlayerTouchSurfacePanView, coordinator _: ()) {
        view.recognizer.view?.removeGestureRecognizer(view.recognizer)
    }
}

final class PlayerTouchSurfacePanView: UIView, UIGestureRecognizerDelegate {
    let recognizer = UIPanGestureRecognizer()
    var onChanged: (CGFloat, CGFloat) -> Void = { _, _ in }
    var onEnded: () -> Void = {}

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        recognizer.allowedTouchTypes = [NSNumber(value: UITouch.TouchType.indirect.rawValue)]
        recognizer.cancelsTouchesInView = false
        // Clickpad presses must reach the focused view right away, even while a finger rests on the surface.
        recognizer.allowedPressTypes = []
        recognizer.delaysTouchesEnded = false
        recognizer.delegate = self
        recognizer.addTarget(self, action: #selector(handlePan(_:)))
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

    @objc private func handlePan(_ recognizer: UIPanGestureRecognizer) {
        switch recognizer.state {
        case .began, .changed:
            onChanged(recognizer.translation(in: recognizer.view).x, recognizer.view?.bounds.width ?? 0)
        case .ended, .cancelled, .failed:
            onEnded()
        default:
            break
        }
    }

    func gestureRecognizer(
        _: UIGestureRecognizer,
        shouldRecognizeSimultaneouslyWith _: UIGestureRecognizer,
    ) -> Bool {
        true
    }
}
