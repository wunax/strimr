import SwiftUI

struct UserMenuToolbarButton: View {
    @Environment(SessionManager.self) private var sessionManager
    @Environment(PlexAPIContext.self) private var plexApiContext
    @Environment(MainCoordinator.self) private var coordinator
    @State private var navPath = NavigationPath()

    var body: some View {
        @Bindable var coordinator = coordinator
        Button {
            coordinator.isPresentingUserMenu = true
        } label: {
            avatarView
        }
        .accessibilityLabel(Text("tabs.more"))
        .sheet(isPresented: $coordinator.isPresentingUserMenu) {
            NavigationStack(path: $navPath) {
                UserMenuView()
                    .navigationDestination(for: MediaItem.self) { media in
                    MediaDetailView(
                        viewModel: MediaDetailViewModel(media: media, context: plexApiContext),
                        onPlay: { ratingKey, downloadPath in
                            coordinator.showPlayer(for: ratingKey, downloadPath: downloadPath)
                        },
                        onPlayFromStart: { ratingKey, downloadPath in
                            coordinator.showPlayer(for: ratingKey, shouldResumeFromOffset: false, downloadPath: downloadPath)
                        },
                        onSelectMedia: { item in
                            navPath.append(item)
                        }
                    )
                }
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
        guard let thumb = sessionManager.user?.thumb else {
            return nil
        }
        return URL(string: thumb)
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
            ToolbarItem(placement: .topBarTrailing) {
                UserMenuToolbarButton()
            }
        }
    }
}

extension View {
    func userMenuToolbar() -> some View {
        modifier(UserMenuToolbarModifier())
    }
}
