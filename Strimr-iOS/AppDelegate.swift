import SwiftUI

final class AppDelegate: NSObject, UIApplicationDelegate {
    private static var orientationMasks: [String: UIInterfaceOrientationMask] = [:]

    static func orientationMask(for scene: UIWindowScene) -> UIInterfaceOrientationMask {
        orientationMasks[scene.session.persistentIdentifier] ?? .all
    }

    static func setOrientationMask(_ mask: UIInterfaceOrientationMask, for scene: UIWindowScene) {
        if mask == .all {
            orientationMasks.removeValue(forKey: scene.session.persistentIdentifier)
        } else {
            orientationMasks[scene.session.persistentIdentifier] = mask
        }
    }

    func application(
        _: UIApplication,
        supportedInterfaceOrientationsFor window: UIWindow?,
    ) -> UIInterfaceOrientationMask {
        guard let scene = window?.windowScene else { return .all }
        return Self.orientationMask(for: scene)
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
