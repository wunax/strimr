import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all {
        didSet {
            for case let windowScene as UIWindowScene in UIApplication.shared.connectedScenes {
                windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock))
                for window in windowScene.windows {
                    window.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
                }
            }
        }
    }

    static func lockToCurrentOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            orientationLock = .all
            return
        }
        switch scene.effectiveGeometry.interfaceOrientation {
        case .portrait:
            orientationLock = .portrait
        case .portraitUpsideDown:
            orientationLock = .portraitUpsideDown
        case .landscapeLeft:
            orientationLock = .landscapeLeft
        case .landscapeRight:
            orientationLock = .landscapeRight
        case .unknown:
            orientationLock = .all
        @unknown default:
            orientationLock = .all
        }
    }

    func application(_: UIApplication, supportedInterfaceOrientationsFor _: UIWindow?) -> UIInterfaceOrientationMask {
        Self.orientationLock
    }

    func application(
        _: UIApplication,
        handleEventsForBackgroundURLSession identifier: String,
        completionHandler: @escaping () -> Void,
    ) {
        guard identifier == DownloadManager.backgroundSessionIdentifier else {
            completionHandler()
            return
        }

        // Registered synchronously so the handler always exists before the session delivers its events.
        MainActor.assumeIsolated {
            DownloadManager.shared?.setBackgroundEventsCompletionHandler(completionHandler)
        }
    }
}
