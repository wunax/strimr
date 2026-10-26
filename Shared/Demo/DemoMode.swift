#if DEBUG
    import Foundation

    /// Screenshot mode: the app shows a fixed catalog read from the Mac instead of a real server. Debug builds only.
    enum DemoMode {
        static let isEnabled = ProcessInfo.processInfo.arguments.contains("-ScreenshotMode")

        static let server = ServerIdentity(provider: .jellyfin, id: "strimr-demo")
        static let userID = "strimr-demo-user"

        /// Set by `-ScreenshotRoute <route>`, which lands in the arguments domain of `UserDefaults`.
        static var route: String? {
            UserDefaults.standard.string(forKey: "ScreenshotRoute")
        }

        static var contentDirectory: URL? {
            guard let path = ProcessInfo.processInfo.environment["STRIMR_DEMO_CONTENT"], !path.isEmpty else {
                return nil
            }
            return URL(fileURLWithPath: path, isDirectory: true)
        }
    }
#endif
