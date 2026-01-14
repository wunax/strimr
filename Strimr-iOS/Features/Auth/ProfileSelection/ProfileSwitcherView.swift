import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var isShowingLogoutConfirmation = false
    @State private var isShowingErrorDetails = false

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.05, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing,
            )
            .ignoresSafeArea()

            ScrollView {
                VStack(spacing: 24) {
                    header
                    if let error = viewModel.errorMessage {
                        errorCard(error)
                    }
                    profilesGrid
                }
                .padding(.horizontal, 20)
                .padding(.top, 32)
                .padding(.bottom, 12)
            }
        }
        .navigationTitle("auth.profile.title")
        .navigationBarTitleDisplayMode(.inline)
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
        .refreshable { await viewModel.loadUsers() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("auth.profile.pin.title")
                        .font(.headline)

                    Text("auth.profile.pin.prompt \(user.title)")
                        .foregroundStyle(.secondary)

                    SecureField("auth.profile.pin.placeholder", text: $pinInput)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .focused($isPinFieldFocused)
                        .padding()
                        .background(.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                    Button {
                        let enteredPin = pinInput
                        Task {
                            await viewModel.switchToUser(user, pin: enteredPin)
                        }
                        resetPinPrompt()
                    } label: {
                        Text("common.actions.switchProfile")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(pinInput.count < 4)

                    Button("common.actions.cancel", role: .cancel) {
                        resetPinPrompt()
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
                .padding()
                .navigationTitle("auth.profile.pin.required")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    isPinFieldFocused = true
                }
            }
        }
        .onChange(of: pinInput) { _, newValue in
            pinInput = String(newValue.filter(\.isNumber).prefix(4))
        }
        .onChange(of: viewModel.errorDetails) { _, _ in
            isShowingErrorDetails = false
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("auth.profile.header.title")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 18) {
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
                    .tint(.white)
                Text("auth.profile.loading")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } else {
            Text("auth.profile.empty")
                .foregroundStyle(.white.opacity(0.7))
                .frame(maxWidth: .infinity, alignment: .leading)
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
            VStack(spacing: 10) {
                avatarView(for: user)
                    .frame(width: 120, height: 120)
                    .overlay(alignment: .topTrailing) {
                        if requiresPin(for: user) {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(8)
                        } else if viewModel.activeUserUUID == user.uuid {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.red)
                                .padding(8)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                Color.white.opacity(viewModel.activeUserUUID == user.uuid ? 0.8 : 0.25),
                                lineWidth: viewModel.activeUserUUID == user.uuid ? 2 : 1,
                            ),
                    )
                    .scaleEffect(viewModel.activeUserUUID == user.uuid ? 1.03 : 1)

                VStack(spacing: 4) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(user.username ?? user.email ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.35))
                ProgressView()
                    .tint(.white)
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
                .padding(24),
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.white)

            if let errorDetails = viewModel.errorDetails {
                DisclosureGroup(
                    isExpanded: $isShowingErrorDetails,
                    content: {
                        Text(errorDetails)
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    label: {
                        Text(isShowingErrorDetails ? "common.actions.hideDetails" : "common.actions.showDetails")
                            .font(.caption)
                            .foregroundStyle(.white.opacity(0.7))
                    },
                )
            }

            Button {
                Task { await viewModel.loadUsers() }
            } label: {
                Text("common.actions.retry")
                    .fontWeight(.semibold)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 10)
                    .background(Color.red)
                    .foregroundStyle(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            }
        }
        .padding()
        .background(Color.white.opacity(0.04))
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
}
