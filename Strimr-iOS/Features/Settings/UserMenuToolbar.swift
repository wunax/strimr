import SwiftUI

struct UserMenuToolbarButton: View {
    @Environment(SessionManager.self) private var sessionManager
    @EnvironmentObject private var coordinator: MainCoordinator
    @State private var isPresentingMenu = false
    @State private var shouldShowLibraries = false

    var body: some View {
        Button {
            isPresentingMenu = true
        } label: {
            avatarView
        }
        .accessibilityLabel(Text("tabs.more"))
        .sheet(isPresented: $isPresentingMenu, onDismiss: {
            guard shouldShowLibraries else { return }
            shouldShowLibraries = false
            coordinator.showLibraryBrowser()
        }) {
            NavigationStack {
                UserMenuView(onShowLibraries: {
                    shouldShowLibraries = true
                    isPresentingMenu = false
                })
            }
        }
    }

    private var avatarView: some View {
        ZStack {
            if let url = avatarURL {
                AsyncImage(url: url) { phase in
                    switch phase {
                    case let .success(image):
                        image
                            .resizable()
                            .scaledToFill()
                    case .empty:
                        placeholderAvatar
                    case .failure:
                        placeholderAvatar
                    @unknown default:
                        placeholderAvatar
                    }
                }
            } else {
                placeholderAvatar
            }
        }
        .frame(width: 28, height: 28)
        .clipShape(Circle())
        .overlay(
            Circle()
                .stroke(.strokeSubtle, lineWidth: 1),
        )
    }

    private var avatarURL: URL? {
        sessionManager.activeProfileAvatarURL
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(.surfaceRaised)
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.textSecondary),
            )
    }
}

private struct UserMenuToolbarModifier: ViewModifier {
    func body(content: Content) -> some View {
        content.toolbar {
            OfflineStatusToolbarItem()
            ToolbarItem(placement: .topBarTrailing) {
                UserMenuToolbarButton()
            }
        }
    }
}

/// The pill has its own background; the Liquid Glass bubble around toolbar items would double it.
private struct OfflineStatusToolbarItem: ToolbarContent {
    var body: some ToolbarContent {
        if #available(iOS 26.0, *) {
            ToolbarItem(placement: .topBarLeading) {
                OfflineStatusPill()
            }
            .sharedBackgroundVisibility(.hidden)
        } else {
            ToolbarItem(placement: .topBarLeading) {
                OfflineStatusPill()
            }
        }
    }
}

extension View {
    func userMenuToolbar() -> some View {
        modifier(UserMenuToolbarModifier())
    }
}
