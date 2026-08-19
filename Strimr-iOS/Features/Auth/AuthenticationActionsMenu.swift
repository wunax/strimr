import SwiftUI

@MainActor
struct AuthenticationActionsMenu: View {
    @Environment(DownloadManager.self) private var downloadManager

    var onChangeProvider: (() -> Void)?
    var onSignOut: (() -> Void)?

    var body: some View {
        Menu {
            if downloadManager.playableCount > 0 {
                NavigationLink {
                    DownloadsView()
                } label: {
                    Label(
                        "downloads.menu.count \(downloadManager.playableCount)",
                        systemImage: "arrow.down.circle.fill",
                    )
                }
            }

            if let onChangeProvider {
                Button(action: onChangeProvider) {
                    Label("provider.change", systemImage: "arrow.left.arrow.right")
                }
            }

            if let onSignOut {
                if downloadManager.playableCount > 0 || onChangeProvider != nil {
                    Divider()
                }
                Button(role: .destructive, action: onSignOut) {
                    Label("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right")
                }
            }
        } label: {
            Image(systemName: "ellipsis")
        }
        .accessibilityLabel("common.actions.more")
    }
}
