import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: ProfileChoice?
    @State private var isShowingProfiles = false
    @FocusState private var focusedUserID: String?

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            Color("Background").ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 32) {
                    header

                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }

                    profilesGrid
                }
                .padding(48)
            }
        }
        .task { await viewModel.load() }
        // Keeps a navigation stack: profiles are pushed from the list.
        .taskPresentation(isPresented: $isShowingProfiles, style: .compactModal, onDismiss: viewModel.refreshChoices) {
            NavigationStack { ProfilesSettingsView() }
        }
        .taskPresentation(
            item: $viewModel.profileNeedingConnection,
            style: .compactModal,
            onDismiss: viewModel.refreshChoices,
        ) { profile in
            TaskModalNavigationView { ProfileDetailView(profileID: profile.id, startsWithNewConnection: true) }
        }
        .onAppear {
            if focusedUserID == nil, let firstUser = viewModel.choices.first {
                focusedUserID = firstUser.id
            }
        }
        .onChange(of: viewModel.choices) { _, newValue in
            if focusedUserID == nil, let firstUser = newValue.first {
                focusedUserID = firstUser.id
            }
        }
        .taskPresentation(item: $pinPromptUser) { user in
            TVPINPadView(
                title: "auth.profile.pin.title",
                message: String(localized: "auth.profile.pin.prompt \(user.name)"),
                onComplete: { pin in
                    pinPromptUser = nil
                    Task { await viewModel.select(user, pin: pin) }
                },
                onCancel: { pinPromptUser = nil },
            )
        }
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 12) {
                Text("auth.profile.title")
                    .font(.largeTitle.bold())
                Text("auth.profile.header.subtitle")
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if viewModel.canManageProfiles {
                Button("profiles.manage") { isShowingProfiles = true }
            }
            if viewModel.canCancel {
                Button("common.actions.cancel") { viewModel.cancel() }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 42)], spacing: 46) {
            if viewModel.choices.isEmpty {
                loadingState
            }

            ForEach(viewModel.choices) { user in
                profileButton(for: user)
            }
        }
    }

    @ViewBuilder
    private var loadingState: some View {
        if viewModel.isLoading {
            HStack(spacing: 12) {
                ProgressView()
                Text("auth.profile.loading")
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            Text("auth.profile.empty")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func profileButton(for user: ProfileChoice) -> some View {
        Button {
            if user.requiresPIN {
                pinPromptUser = user
            } else {
                Task { await viewModel.select(user, pin: nil) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                avatar(for: user)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(borderColor(for: user), lineWidth: user.isActive ? 3 : 1),
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.name)
                        .font(.headline)
                        .lineLimit(1)
                    Text(user.detail ?? "")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .background(Color.white.opacity(0.04))
            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            .padding(.vertical, 4)
        }
        .buttonStyle(.plain)
        .focused($focusedUserID, equals: user.id)
    }

    private func avatar(for user: ProfileChoice) -> some View {
        ZStack {
            if user.isLocal {
                ProfileInitialsAvatar(initials: user.initials)
            } else if let url = user.avatarURL {
                AsyncImage(url: url) { image in
                    image
                        .resizable()
                        .scaledToFill()
                } placeholder: {
                    placeholderAvatar
                }
            } else {
                placeholderAvatar
            }
        }
        .overlay {
            if viewModel.switchingID == user.id {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                ProgressView()
            } else if user.requiresPIN {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(12)
            } else if user.isActive {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(.green.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(12)
            }
        }
    }

    private var placeholderAvatar: some View {
        LinearGradient(
            colors: [
                Color.red.opacity(0.85),
                Color.red.opacity(0.5),
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay(
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(32),
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .font(.headline)

            Button {
                Task { await viewModel.load() }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.clockwise")
                    Text("common.actions.retry")
                        .fontWeight(.semibold)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Color.red)
                .foregroundStyle(.white)
                .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
            .buttonStyle(.plain)
        }
        .padding()
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    private func borderColor(for user: ProfileChoice) -> Color {
        if user.isActive {
            return .brandPrimary
        }
        return .white.opacity(0.2)
    }
}
