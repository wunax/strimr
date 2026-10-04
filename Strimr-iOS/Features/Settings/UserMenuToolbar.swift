import SwiftUI

struct UserMenuToolbarButton: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isPresentingMenu = false

    var body: some View {
        Button {
            isPresentingMenu = true
        } label: {
            avatarView
        }
        .accessibilityLabel(Text("tabs.more"))
        .sheet(isPresented: $isPresentingMenu) {
            NavigationStack {
                UserMenuView()
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
                .stroke(Color.primary.opacity(0.12), lineWidth: 1),
        )
    }

    private var avatarURL: URL? {
        sessionManager.activeProfileAvatarURL
    }

    private var placeholderAvatar: some View {
        Circle()
            .fill(Color.gray.opacity(0.2))
            .overlay(
                Image(systemName: "person.crop.circle.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(Color.gray.opacity(0.7)),
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
