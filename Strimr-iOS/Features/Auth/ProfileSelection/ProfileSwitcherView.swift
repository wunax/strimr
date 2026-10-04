import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: ProfileChoice?
    @State private var pinInput: String = ""
    @FocusState private var isPinFieldFocused: Bool
    @State private var isShowingProfiles = false

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
            if viewModel.canCancel {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") { viewModel.cancel() }
                }
            }
            if viewModel.canManageProfiles {
                ToolbarItem(placement: .topBarTrailing) {
                    Button("profiles.manage") { isShowingProfiles = true }
                }
            }
        }
        .sheet(isPresented: $isShowingProfiles, onDismiss: viewModel.refreshChoices) {
            NavigationStack { ProfilesSettingsView() }
        }
        .sheet(item: $viewModel.profileNeedingConnection, onDismiss: viewModel.refreshChoices) { profile in
            NavigationStack { ProfileDetailView(profileID: profile.id, startsWithNewConnection: true) }
        }
        .task { await viewModel.load() }
        .refreshable { await viewModel.load() }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            NavigationStack {
                VStack(alignment: .leading, spacing: 16) {
                    Text("auth.profile.pin.title")
                        .font(.headline)

                    Text("auth.profile.pin.prompt \(user.name)")
                        .foregroundStyle(.secondary)

                    SecureField("auth.profile.pin.placeholder", text: $pinInput)
                        .keyboardType(.numberPad)
                        .textContentType(.password)
                        .focused($isPinFieldFocused)
                        .padding()
                        .background(.gray.opacity(0.12))
                        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

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
                .font(.largeTitle.bold())
                .foregroundStyle(.white)
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.white.opacity(0.7))
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 120), spacing: 16)], spacing: 18) {
            if viewModel.choices.isEmpty {
                loadingState
            }
            ForEach(viewModel.choices) { choice in
                profileCard(for: choice)
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

    private func profileCard(for user: ProfileChoice) -> some View {
        Button {
            if user.requiresPIN {
                pinPromptUser = user
                pinInput = ""
                isPinFieldFocused = true
            } else {
                Task { await viewModel.select(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 10) {
                avatarView(for: user)
                    .frame(width: 120, height: 120)
                    .overlay(alignment: .topTrailing) {
                        if user.requiresPIN {
                            Image(systemName: "lock.fill")
                                .foregroundStyle(.white.opacity(0.9))
                                .padding(8)
                        } else if user.isActive {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundStyle(Color.red)
                                .padding(8)
                        }
                    }
                    .overlay(
                        RoundedRectangle(cornerRadius: 14, style: .continuous)
                            .stroke(
                                Color.white.opacity(user.isActive ? 0.8 : 0.25),
                                lineWidth: user.isActive ? 2 : 1,
                            ),
                    )
                    .scaleEffect(user.isActive ? 1.03 : 1)

                VStack(spacing: 4) {
                    Text(user.name)
                        .font(.headline)
                        .foregroundStyle(.white)
                        .lineLimit(1)
                    Text(user.detail ?? "")
                        .font(.caption)
                        .foregroundStyle(.white.opacity(0.6))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }

    private func avatarView(for user: ProfileChoice) -> some View {
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
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
        .overlay {
            if viewModel.switchingID == user.id {
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

            Button {
                Task { await viewModel.load() }
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
            await viewModel.select(user, pin: enteredPin)
        }
        resetPinPrompt()
    }
}
