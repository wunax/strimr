import Foundation
#if os(macOS)
    import AppKit
#else
    import UIKit
#endif

/// Opens and detects the apps behind external players.
enum ExternalPlayerApps {
    static func open(_ request: ExternalLaunchRequest) async -> Bool {
        #if os(macOS)
            switch request {
            case let .url(url):
                return NSWorkspace.shared.open(url)
            case let .open(url, bundleID):
                guard let application = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
                    return false
                }
                do {
                    _ = try await NSWorkspace.shared.open(
                        [url],
                        withApplicationAt: application,
                        configuration: NSWorkspace.OpenConfiguration(),
                    )
                    return true
                } catch {
                    return false
                }
            }
        #else
            guard case let .url(url) = request else { return false }
            return await UIApplication.shared.open(url)
        #endif
    }

    /// iOS and tvOS only see the schemes declared in `LSApplicationQueriesSchemes`.
    static func isInstalled(_ player: ExternalPlayerID, platform: Platform = .current) -> Bool {
        guard let strategy = player.launchStrategy(on: platform) else { return false }
        #if os(macOS)
            switch strategy {
            case .template:
                guard let url = player.scheme(on: platform).flatMap({ URL(string: "\($0)://") }) else { return false }
                return NSWorkspace.shared.urlForApplication(toOpen: url) != nil
            case let .application(bundleID):
                return NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) != nil
            }
        #else
            guard case .template = strategy,
                  let url = player.scheme(on: platform).flatMap({ URL(string: "\($0)://") })
            else { return false }
            return UIApplication.shared.canOpenURL(url)
        #endif
    }
}
