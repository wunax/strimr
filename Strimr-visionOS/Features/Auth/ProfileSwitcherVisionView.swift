import SwiftUI

@MainActor
struct ProfileSwitcherVisionView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 32) {
                header
                if let error = viewModel.errorMessage {
                    errorCard(error)
                }
                profilesGrid
            }
            .padding(40)
        }
        .navigationTitle("auth.profile.title")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button(role: .destructive) {
                    isShowingLogoutConfirmation = true
                } label: {
                    Image(systemName: "rectangle.portrait.and.arrow.right")
                }
                .accessibilityLabel("common.actions.logOut")
            }
        }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .task { await viewModel.loadUsers() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("auth.profile.pin.title")
                        .font(.headline)

                    let userDisplayName: String = user.friendlyName ?? user.title ?? "?"
                    Text("auth.profile.pin.prompt \(userDisplayName)")
                        .foregroundStyle(.secondary)

                    SecureField("auth.profile.pin.placeholder", text: $pinInput)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .focused($isPinFieldFocused)
                        .padding()
                        .background(.secondary.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button("common.actions.cancel", role: .cancel) {
                        resetPinPrompt()
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
                .padding(24)
                .navigationTitle("auth.profile.pin.required")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    isPinFieldFocused = true
                }
            }
        }
        .onChange(of: pinInput) { _, newValue in
            let sanitizedValue = String(newValue.filter(\.isNumber).prefix(4))
            if sanitizedValue != pinInput {
                pinInput = sanitizedValue
                return
            }
            submitPinIfComplete()
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("auth.profile.header.title")
                .font(.extraLargeTitle)
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.secondary)
                .font(.title3)
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 160), spacing: 24)], spacing: 24) {
            if viewModel.users.isEmpty {
                loadingState
            }
            ForEach(viewModel.users) { user in
                profileCard(for: user)
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
            .frame(maxWidth: .infinity, alignment: .center)
            .padding()
        } else {
            Text("auth.profile.empty")
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .center)
                .padding()
        }
    }

    private func profileCard(for user: PlexHomeUser) -> some View {
        Button {
            if requiresPin(for: user) {
                pinPromptUser = user
                pinInput = ""
                isPinFieldFocused = true
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 12) {
                avatarView(for: user)
                    .frame(width: 140, height: 140)
                    .overlay(alignment: .topTrailing) {
                        if requiresPin(for: user) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(10)
                        } else if viewModel.activeUserUUID == user.uuid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.red)
                                .padding(10)
                        }
                    }

                VStack(spacing: 4) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.headline)
                        .lineLimit(1)
                    Text(user.username ?? user.email ?? "")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
        .hoverEffect()
    }

    private func avatarView(for user: PlexHomeUser) -> some View {
        ZStack {
            if let url = user.thumb {
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
        .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                RoundedRectangle(cornerRadius: 20, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
            }
        }
    }

    private var placeholderAvatar: some View {
        LinearGradient(
            colors: [Color.red.opacity(0.8), Color.red.opacity(0.5)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing,
        )
        .overlay(
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(30),
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)

            Button {
                Task { await viewModel.loadUsers() }
            } label: {
                Text("common.actions.retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(.red)
        }
        .padding()
        .background(.secondary.opacity(0.08))
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func requiresPin(for user: PlexHomeUser) -> Bool {
        user.protected ?? false
    }

    private func resetPinPrompt() {
        pinPromptUser = nil
        pinInput = ""
        isPinFieldFocused = false
    }

    private func submitPinIfComplete() {
        guard pinInput.count == 4 else { return }
        guard let user = pinPromptUser else { return }

        let enteredPin = pinInput
        Task {
            await viewModel.switchToUser(user, pin: enteredPin)
        }
        resetPinPrompt()
    }
}
