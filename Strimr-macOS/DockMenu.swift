import AppKit
import SwiftUI

/// The Dock menu, with the same actions as the quick actions on iOS.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDockMenu(_: NSApplication) -> NSMenu? {
        guard let snapshot = AppEntryPoints.shared.snapshot else { return nil }
        let menu = NSMenu()
        if let resume = snapshot.resume {
            menu.addItem(item(
                title: String(localized: "quickActions.resume.title \(resume.primaryLabel)"),
                link: DeepLink(
                    .play(.item(resume.identity, kind: resume.type), mode: .resume),
                    profile: snapshot.profileID,
                ),
            ))
        }
        menu.addItem(item(
            title: String(localized: "quickActions.search"),
            link: DeepLink(.search(nil), profile: snapshot.profileID),
        ))
        menu.addItem(item(
            title: String(localized: "quickActions.downloads"),
            link: DeepLink(.tab(.downloads), profile: snapshot.profileID),
        ))
        if snapshot.hasLiveTV {
            menu.addItem(item(
                title: String(localized: "quickActions.liveTV"),
                link: DeepLink(.tab(.liveTV), profile: snapshot.profileID),
            ))
        }
        return menu
    }

    private func item(title: String, link: DeepLink) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(open(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = link.url
        return item
    }

    @objc private func open(_ sender: NSMenuItem) {
        guard let url = sender.representedObject as? URL else { return }
        NSApp.activate()
        DeepLinkRouter.shared.receive(url)
    }
}

/// The Go menu, which opens the main sections from the keyboard.
struct GoCommands: Commands {
    var body: some Commands {
        CommandMenu("commands.go") {
            button("tabs.home", tab: .home, key: "1")
            button("tabs.search", tab: .search, key: "2")
            button("downloads.title", tab: .downloads, key: "3")
            button("livetv.title", tab: .liveTV, key: "4")
            button("tabs.explore", tab: .explore, key: "5")
        }
    }

    private func button(_ title: LocalizedStringKey, tab: DeepLink.Tab, key: KeyEquivalent) -> some View {
        Button(title) {
            DeepLinkRouter.shared.receive(DeepLink(.tab(tab)))
        }
        .keyboardShortcut(key, modifiers: .command)
    }
}
