import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            LinearGradient(
                colors: [Color.black, Color(red: 0.08, green: 0.05, blue: 0.07)],
                startPoint: .topLeading,
                endPoint: .bottomTrailing
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
        .navigationTitle("Select Profile")
        .navigationBarTitleDisplayMode(.inline)
        .task { await viewModel.loadUsers() }
        .refreshable { await viewModel.loadUsers() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("Enter PIN")
                        .font(.headline)

                    Text("Enter the 4-digit PIN for \(user.title).")
                        .foregroundStyle(.secondary)

                    TextField("PIN", text: $pinInput)
                        .keyboardType(.numberPad)
                        .textContentType(.oneTimeCode)
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
                        Text("Switch Profile")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.brandPrimary)
                    .disabled(pinInput.count < 4)

                    Button("Cancel", role: .cancel) {
                        resetPinPrompt()
                    }
                    .frame(maxWidth: .infinity)

                    Spacer()
                }
                .padding()
                .navigationTitle("PIN Required")
                .navigationBarTitleDisplayMode(.inline)
                .onAppear {
                    isPinFieldFocused = true
                }
            }
        }
        .onChange(of: pinInput) { _, newValue in
            pinInput = String(newValue.filter(\.isNumber).prefix(4))
        }
    }

    private var header: some View {
        VStack(spacing: 8) {
            Text("Who's watching?")
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("Choose a profile to continue")
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
                Text("Loading profiles...")
                    .foregroundStyle(.white.opacity(0.7))
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        } else {
            Text("No profiles available.")
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
                            .stroke(Color.white.opacity(viewModel.activeUserUUID == user.uuid ? 0.8 : 0.25), lineWidth: viewModel.activeUserUUID == user.uuid ? 2 : 1)
                    )
                    .scaleEffect(viewModel.activeUserUUID == user.uuid ? 1.03 : 1)

                VStack(spacing: 4) {
                    Text(user.friendlyName ?? user.title)
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
            endPoint: .bottomTrailing
        )
        .overlay(
            Image(systemName: "person.crop.square.fill")
                .resizable()
                .scaledToFit()
                .foregroundStyle(.white.opacity(0.9))
                .padding(24)
        )
    }

    private func errorCard(_ message: String) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(message)
                .foregroundStyle(.white)

            Button {
                Task { await viewModel.loadUsers() }
            } label: {
                Text("Retry")
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

#Preview {
    let context = PlexAPIContext()
    let session = SessionManager(context: context)
    NavigationStack {
        ProfileSwitcherView(
            viewModel: ProfileSwitcherViewModel(context: context, sessionManager: session)
        )
    }
    .environment(context)
    .environment(session)
}
