import AppKit
import Observation
import SwiftUI

@MainActor
@Observable
final class PlayerFullscreenCoordinator {
    private(set) var isFullScreen = false
    private(set) var isTransitioning = false

    @ObservationIgnored private weak var window: NSWindow?
    @ObservationIgnored private var notificationObservers: [NSObjectProtocol] = []

    func attach(to window: NSWindow) {
        if let currentWindow = self.window {
            if currentWindow === window {
                if !isFullScreen, !isTransitioning {
                    configureWindowForFullScreen(currentWindow)
                }
            }
            return
        }

        self.window = window
        configureWindowForFullScreen(window)
        updateState()

        let notificationCenter = NotificationCenter.default
        notificationObservers = [
            notificationCenter.addObserver(
                forName: NSWindow.willEnterFullScreenNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isFullScreen = true
                    self?.isTransitioning = true
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.didEnterFullScreenNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isFullScreen = true
                    self?.isTransitioning = false
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.willExitFullScreenNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.isTransitioning = true
                }
            },
            notificationCenter.addObserver(
                forName: NSWindow.didExitFullScreenNotification,
                object: window,
                queue: .main,
            ) { [weak self] _ in
                MainActor.assumeIsolated {
                    guard let self else { return }
                    self.isFullScreen = false
                    self.isTransitioning = false
                    if let window = self.window {
                        self.configureWindowForFullScreen(window)
                    }
                }
            },
        ]
    }

    func toggleFullScreen() {
        guard !isTransitioning, let window else { return }
        configureWindowForFullScreen(window)
        window.toggleFullScreen(nil)
    }

    func detach() {
        let notificationCenter = NotificationCenter.default
        notificationObservers.forEach(notificationCenter.removeObserver)
        notificationObservers.removeAll()
        window = nil
        isFullScreen = false
        isTransitioning = false
    }

    private func updateState() {
        isFullScreen = window?.styleMask.contains(.fullScreen) == true
    }

    private func configureWindowForFullScreen(_ window: NSWindow) {
        let requiresUpdate = !window.styleMask.contains(.resizable)
            || window.collectionBehavior.contains(.fullScreenAuxiliary)
            || !window.collectionBehavior.contains(.fullScreenPrimary)
            || window.standardWindowButton(.zoomButton)?.isEnabled != true

        guard requiresUpdate else { return }

        window.styleMask.insert(.resizable)
        window.collectionBehavior.remove(.fullScreenAuxiliary)
        window.collectionBehavior.insert(.fullScreenPrimary)
        window.standardWindowButton(.zoomButton)?.isEnabled = true
    }
}

struct PlayerWindowReader: NSViewRepresentable {
    var onWindowAvailable: (NSWindow) -> Void

    func makeNSView(context _: Context) -> PlayerWindowReaderView {
        PlayerWindowReaderView(onWindowAvailable: onWindowAvailable)
    }

    func updateNSView(_ nsView: PlayerWindowReaderView, context _: Context) {
        nsView.onWindowAvailable = onWindowAvailable
        nsView.reportWindow()
    }
}

final class PlayerWindowReaderView: NSView {
    var onWindowAvailable: (NSWindow) -> Void

    init(onWindowAvailable: @escaping (NSWindow) -> Void) {
        self.onWindowAvailable = onWindowAvailable
        super.init(frame: .zero)
    }

    @available(*, unavailable)
    required init?(coder _: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        reportWindow()
    }

    func reportWindow() {
        guard let window else { return }
        onWindowAvailable(window)
    }
}
