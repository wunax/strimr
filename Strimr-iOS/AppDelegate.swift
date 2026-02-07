import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    static var orientationLock = UIInterfaceOrientationMask.all {
        didSet {
            for scene in UIApplication.shared.connectedScenes {
                if let windowScene = scene as? UIWindowScene {
                    windowScene.requestGeometryUpdate(.iOS(interfaceOrientations: orientationLock))
                }
            }
            if let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene {
                scene.windows.first?.rootViewController?.setNeedsUpdateOfSupportedInterfaceOrientations()
            }
        }
    }

    static func lockToCurrentOrientation() {
        guard let scene = UIApplication.shared.connectedScenes.first as? UIWindowScene else {
            orientationLock = .all
            return
        }
        switch scene.interfaceOrientation {
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

        Task { @MainActor in
            DownloadManager.shared?.setBackgroundEventsCompletionHandler(completionHandler)
        }
    }
}
