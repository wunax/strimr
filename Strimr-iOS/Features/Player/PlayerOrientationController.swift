import Observation
import SwiftUI
import UIKit

@MainActor
@Observable
final class PlayerOrientationController {
    private(set) var isLocked = false
    private(set) var isReadyForPresentation = false

    @ObservationIgnored private weak var host: UIViewController?
    @ObservationIgnored private weak var scene: UIWindowScene?
    @ObservationIgnored private var previousMask: UIInterfaceOrientationMask?
    @ObservationIgnored private var entryOrientation: UIInterfaceOrientation?
    @ObservationIgnored private var didAutomaticallyRotate = false
    @ObservationIgnored private var isActive = false
    @ObservationIgnored private var didConsiderAutomaticRotation = false
    @ObservationIgnored private var videoSize: CGSize?
    @ObservationIgnored private var isEnabled = false
    @ObservationIgnored private var isForeground = false
    @ObservationIgnored private var pendingMask: UIInterfaceOrientationMask?
    @ObservationIgnored private var pendingDeadline: ContinuousClock.Instant?
    @ObservationIgnored private var requestID = UUID()
    @ObservationIgnored private var presentationTimeoutTask: Task<Void, Never>?

    func start() {
        isActive = true
        isReadyForPresentation = false
    }

    func attach(_ host: UIViewController) {
        guard let scene = host.view.window?.windowScene else { return }
        self.host = host
        self.scene = scene
        if previousMask == nil {
            previousMask = AppDelegate.orientationMask(for: scene)
            entryOrientation = scene.interfaceOrientation
        }
        if let pendingMask, let currentMask = mask(for: scene.interfaceOrientation),
           pendingMask.contains(currentMask)
        {
            self.pendingMask = nil
            pendingDeadline = nil
            finishInitialPresentation()
            if isLocked {
                AppDelegate.setOrientationMask(currentMask, for: scene)
                invalidateSupportedOrientations()
            }
        }
        considerAutomaticRotation()
    }

    func update(videoSize: CGSize?, enabled: Bool, isForeground: Bool) {
        self.videoSize = videoSize
        isEnabled = enabled
        self.isForeground = isForeground
        considerAutomaticRotation()
    }

    func playbackDidFail() {
        guard isActive else { return }
        didConsiderAutomaticRotation = true
        finishInitialPresentation()
    }

    func stop() {
        isActive = false
        finishInitialPresentation()
        requestID = UUID()
        pendingMask = nil
        pendingDeadline = nil
        isLocked = false
        if let scene, let previousMask {
            AppDelegate.setOrientationMask(previousMask, for: scene)
            invalidateSupportedOrientations()
            if didAutomaticallyRotate, let entryOrientation, let entryMask = mask(for: entryOrientation),
               previousMask.contains(entryMask)
            {
                restoreEntryOrientation(entryMask, in: scene)
            }
        }
        previousMask = nil
        entryOrientation = nil
        didAutomaticallyRotate = false
        didConsiderAutomaticRotation = false
    }

    private func restoreEntryOrientation(_ mask: UIInterfaceOrientationMask, in scene: UIWindowScene) {
        // Return to the browsing orientation once the player has finished dismissing.
        let restore = { [self, weak scene] in
            guard !isActive, let scene, scene.activationState == .foregroundActive else { return }
            invalidateSupportedOrientations()
            scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { error in
                Task { @MainActor in ErrorReporter.capture(error) }
            }
        }
        if let coordinator = host?.transitionCoordinator,
           coordinator.animate(alongsideTransition: nil, completion: { _ in restore() })
        {
            return
        }
        restore()
    }

    func toggleLock() {
        guard isActive, let scene else { return }
        // A manual choice while media is loading must take precedence over the startup preference.
        didConsiderAutomaticRotation = true
        requestID = UUID()
        if isLocked {
            isLocked = false
            pendingMask = nil
            pendingDeadline = nil
            AppDelegate.setOrientationMask(previousMask ?? .all, for: scene)
            invalidateSupportedOrientations()
            finishInitialPresentation()
        } else {
            if pendingMask == nil {
                finishInitialPresentation()
            }
            let mask: UIInterfaceOrientationMask
            if let pendingMask, let pendingDeadline, ContinuousClock.now < pendingDeadline {
                mask = pendingMask
            } else if let currentMask = self.mask(for: scene.interfaceOrientation) {
                mask = currentMask
            } else {
                return
            }
            let oldMask = AppDelegate.orientationMask(for: scene)
            isLocked = true
            AppDelegate.setOrientationMask(mask, for: scene)
            requestRotation(to: mask, restoringOnFailure: oldMask)
        }
    }

    private func considerAutomaticRotation() {
        guard isActive, !didConsiderAutomaticRotation else { return }
        guard isEnabled, UIDevice.current.userInterfaceIdiom == .phone, !isLocked else {
            didConsiderAutomaticRotation = true
            finishInitialPresentation()
            return
        }
        guard isForeground, let scene, scene.activationState == .foregroundActive,
              let videoSize, videoSize.width > 0, videoSize.height > 0
        else { return }

        // Once per player presentation, including when the first video is portrait.
        didConsiderAutomaticRotation = true
        guard videoSize.width > videoSize.height, !scene.interfaceOrientation.isLandscape else {
            finishInitialPresentation()
            return
        }
        let allowedLandscape = AppDelegate.orientationMask(for: scene).intersection(.landscape)
        guard !allowedLandscape.isEmpty else {
            finishInitialPresentation()
            return
        }
        didAutomaticallyRotate = true
        requestRotation(to: allowedLandscape, isAutomatic: true)
    }

    private func finishInitialPresentation() {
        presentationTimeoutTask?.cancel()
        presentationTimeoutTask = nil
        isReadyForPresentation = true
    }

    private func requestRotation(
        to mask: UIInterfaceOrientationMask,
        restoringOnFailure previousMask: UIInterfaceOrientationMask? = nil,
        isAutomatic: Bool = false,
    ) {
        guard let scene else { return }
        let id = UUID()
        requestID = id
        pendingMask = mask
        pendingDeadline = .now.advanced(by: .seconds(1))
        invalidateSupportedOrientations()
        if isAutomatic {
            // UIKit may decline a request without delivering a transition callback.
            presentationTimeoutTask = Task { [weak self] in
                do {
                    try await Task.sleep(for: .seconds(2))
                } catch {
                    return
                }
                guard let self, isActive else { return }
                finishInitialPresentation()
            }
        }
        scene.requestGeometryUpdate(.iOS(interfaceOrientations: mask)) { [weak self] error in
            Task { @MainActor in
                guard let self, self.isActive, self.requestID == id else { return }
                self.pendingMask = nil
                self.pendingDeadline = nil
                self.finishInitialPresentation()
                if isAutomatic {
                    self.didAutomaticallyRotate = false
                }
                if let previousMask {
                    self.isLocked = false
                    AppDelegate.setOrientationMask(previousMask, for: scene)
                    self.invalidateSupportedOrientations()
                }
                ErrorReporter.capture(error)
            }
        }
    }

    private func invalidateSupportedOrientations() {
        var controller = host
        while let current = controller {
            current.setNeedsUpdateOfSupportedInterfaceOrientations()
            controller = current.parent
        }
        let windows = host?.view.window.map { [$0] } ?? scene?.windows ?? []
        for window in windows {
            controller = window.rootViewController
            while let current = controller {
                current.setNeedsUpdateOfSupportedInterfaceOrientations()
                controller = current.presentedViewController
            }
        }
    }

    private func mask(for orientation: UIInterfaceOrientation) -> UIInterfaceOrientationMask? {
        switch orientation {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeLeft
        case .landscapeRight: .landscapeRight
        default: nil
        }
    }
}

struct PlayerOrientationHost: UIViewControllerRepresentable {
    let controller: PlayerOrientationController

    func makeUIViewController(context _: Context) -> OrientationViewController {
        OrientationViewController(controller: controller)
    }

    func updateUIViewController(_: OrientationViewController, context _: Context) {}

    final class OrientationViewController: UIViewController {
        private let controller: PlayerOrientationController

        init(controller: PlayerOrientationController) {
            self.controller = controller
            super.init(nibName: nil, bundle: nil)
        }

        @available(*, unavailable)
        required init?(coder _: NSCoder) {
            fatalError("init(coder:) is unavailable")
        }

        override func loadView() {
            view = UIView()
            view.isUserInteractionEnabled = false
        }

        override func viewDidAppear(_ animated: Bool) {
            super.viewDidAppear(animated)
            controller.attach(self)
        }

        override func viewWillTransition(to size: CGSize, with coordinator: UIViewControllerTransitionCoordinator) {
            super.viewWillTransition(to: size, with: coordinator)
            coordinator.animate(alongsideTransition: nil) { [weak self] _ in
                guard let self else { return }
                controller.attach(self)
            }
        }
    }
}
