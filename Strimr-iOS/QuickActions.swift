import UIKit

/// The quick actions on the app icon. Each one carries the link it opens.
@MainActor
enum QuickActions {
    private static let linkKey = "link"

    static func update(_ snapshot: AppEntryPoints.Snapshot?) {
        guard let snapshot else {
            UIApplication.shared.shortcutItems = []
            return
        }
        var items: [UIApplicationShortcutItem] = []
        if let resume = snapshot.resume {
            items.append(item(
                type: "resume",
                title: String(localized: "quickActions.resume"),
                subtitle: resume.primaryLabel,
                systemImage: "play.fill",
                link: DeepLink(
                    .play(.item(resume.identity, kind: resume.type), mode: .resume),
                    profile: snapshot.profileID,
                ),
            ))
        }
        items.append(item(
            type: "search",
            title: String(localized: "quickActions.search"),
            systemImage: "magnifyingglass",
            link: DeepLink(.search(nil), profile: snapshot.profileID),
        ))
        items.append(item(
            type: "downloads",
            title: String(localized: "quickActions.downloads"),
            systemImage: "arrow.down.circle",
            link: DeepLink(.tab(.downloads), profile: snapshot.profileID),
        ))
        if snapshot.hasLiveTV {
            items.append(item(
                type: "liveTV",
                title: String(localized: "quickActions.liveTV"),
                systemImage: "tv",
                link: DeepLink(.tab(.liveTV), profile: snapshot.profileID),
            ))
        }
        UIApplication.shared.shortcutItems = items
    }

    static func link(for item: UIApplicationShortcutItem) -> DeepLink? {
        guard let string = item.userInfo?[linkKey] as? String, let url = URL(string: string) else { return nil }
        return DeepLink(url: url)
    }

    private static func item(
        type: String,
        title: String,
        subtitle: String? = nil,
        systemImage: String,
        link: DeepLink,
    ) -> UIApplicationShortcutItem {
        UIApplicationShortcutItem(
            type: "\(Bundle.main.bundleIdentifier ?? "strimr").\(type)",
            localizedTitle: title,
            localizedSubtitle: subtitle,
            icon: UIApplicationShortcutIcon(systemImageName: systemImage),
            userInfo: [linkKey: link.url.absoluteString as NSString],
        )
    }
}

/// Receives the quick action that opened or woke the app.
final class SceneDelegate: NSObject, UIWindowSceneDelegate {
    func scene(_: UIScene, willConnectTo _: UISceneSession, options connectionOptions: UIScene.ConnectionOptions) {
        if let item = connectionOptions.shortcutItem {
            receive(item)
        }
    }

    func windowScene(
        _: UIWindowScene,
        performActionFor shortcutItem: UIApplicationShortcutItem,
        completionHandler: @escaping (Bool) -> Void,
    ) {
        completionHandler(receive(shortcutItem))
    }

    @discardableResult
    private func receive(_ item: UIApplicationShortcutItem) -> Bool {
        guard let link = QuickActions.link(for: item) else { return false }
        DeepLinkRouter.shared.receive(link)
        return true
    }
}
