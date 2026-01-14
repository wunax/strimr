import SwiftUI

@MainActor
struct ProfileSwitcherTVView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinPromptUser: PlexHomeUser?
    @State private var pinInput: String = ""
    @State private var isShowingLogoutConfirmation = false
    @FocusState private var focusedUserID: String?
    @State private var isShowingErrorDetails = false

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
        .task { await viewModel.loadUsers() }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
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
        .onAppear {
            if focusedUserID == nil, let firstUser = viewModel.users.first {
                focusedUserID = firstUser.uuid
            }
        }
        .onChange(of: viewModel.users) { _, newValue in
            if focusedUserID == nil, let firstUser = newValue.first {
                focusedUserID = firstUser.uuid
            }
        }
        .sheet(item: $pinPromptUser, onDismiss: resetPinPrompt) { user in
            pinEntrySheet(for: user)
        }
        .onChange(of: pinInput) { _, newValue in
            pinInput = String(newValue.filter(\.isNumber).prefix(4))
        }
        .onChange(of: viewModel.errorDetails) { _, _ in
            isShowingErrorDetails = false
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("auth.profile.title")
                .font(.largeTitle.bold())
            Text("auth.profile.header.subtitle")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private var profilesGrid: some View {
        LazyVGrid(columns: [GridItem(.adaptive(minimum: 240), spacing: 42)], spacing: 46) {
            if viewModel.users.isEmpty {
                loadingState
            }

            ForEach(viewModel.users) { user in
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

    private func profileButton(for user: PlexHomeUser) -> some View {
        Button {
            if requiresPin(for: user) {
                pinPromptUser = user
                pinInput = ""
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(alignment: .leading, spacing: 12) {
                avatar(for: user)
                    .frame(width: 220, height: 220)
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: 18, style: .continuous)
                            .stroke(borderColor(for: user), lineWidth: viewModel.activeUserUUID == user.uuid ? 3 : 1),
                    )

                VStack(alignment: .leading, spacing: 6) {
                    Text(user.friendlyName ?? user.title ?? "?")
                        .font(.headline)
                        .lineLimit(1)
                    Text(user.username ?? user.email ?? "")
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
        .focused($focusedUserID, equals: user.uuid)
    }

    @ViewBuilder
    private func avatar(for user: PlexHomeUser) -> some View {
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
        .overlay {
            if viewModel.switchingUserUUID == user.uuid {
                RoundedRectangle(cornerRadius: 18, style: .continuous)
                    .fill(Color.black.opacity(0.4))
                ProgressView()
            } else if requiresPin(for: user) {
                VStack {
                    HStack {
                        Spacer()
                        Image(systemName: "lock.fill")
                            .foregroundStyle(.white.opacity(0.9))
                    }
                    Spacer()
                }
                .padding(12)
            } else if viewModel.activeUserUUID == user.uuid {
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

            if let errorDetails = viewModel.errorDetails {
                DisclosureGroup(
                    isExpanded: $isShowingErrorDetails,
                    content: {
                        Text(errorDetails)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    },
                    label: {
                        Text(isShowingErrorDetails ? "common.actions.hideDetails" : "common.actions.showDetails")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    },
                )
            }
            Button {
                Task { await viewModel.loadUsers() }
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

    private func pinEntrySheet(for user: PlexHomeUser) -> some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("auth.profile.pin.title")
                .font(.title2.bold())
            Text("auth.profile.pin.prompt \(user.title)")
                .foregroundStyle(.secondary)

            pinDisplay

            keypad

            HStack(spacing: 16) {
                Button("common.actions.cancel", role: .cancel) {
                    resetPinPrompt()
                }
                .frame(maxWidth: .infinity)

                Button {
                    let enteredPin = pinInput
                    Task { await viewModel.switchToUser(user, pin: enteredPin) }
                    resetPinPrompt()
                } label: {
                    Text("common.actions.switchProfile")
                        .frame(maxWidth: .infinity)
                }
                .tint(.brandSecondary)
                .foregroundStyle(.brandSecondaryForeground)
                .disabled(pinInput.count < 4)
            }
            .focusSection()

            Spacer()
        }
        .padding(32)
    }

    private var pinDisplay: some View {
        HStack(spacing: 12) {
            ForEach(0 ..< 4, id: \.self) { index in
                ZStack {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.white.opacity(0.1))
                        .frame(width: 70, height: 70)

                    if index < pinInput.count {
                        Text("•")
                            .font(.title.bold())
                    }
                }
            }
        }
    }

    private let columns = [
        GridItem(.fixed(128), spacing: 16),
        GridItem(.fixed(128), spacing: 16),
        GridItem(.fixed(128), spacing: 16),
    ]

    private let keypadButtonSize = CGSize(width: 64, height: 48)

    private var keypad: some View {
        LazyVGrid(columns: columns) {
            ForEach(["1", "2", "3", "4", "5", "6", "7", "8", "9"], id: \.self) {
                keypadDigitButton($0)
            }

            Color.clear
                .frame(
                    width: keypadButtonSize.width,
                    height: keypadButtonSize.height,
                )

            keypadDigitButton("0")
            keypadDeleteButton()
        }
    }

    private func keypadDigitButton(_ digit: String) -> some View {
        Button {
            appendDigit(digit)
        } label: {
            Text(digit)
                .font(.title2.bold())
                .frame(width: keypadButtonSize.width)
                .padding(.vertical, 16)
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.small)
    }

    private func keypadDeleteButton() -> some View {
        Button {
            deleteDigit()
        } label: {
            Image(systemName: "delete.left")
                .font(.title2.bold())
                .frame(width: keypadButtonSize.width)
                .padding(.vertical, 16)
        }
        .buttonBorderShape(.roundedRectangle(radius: 14))
        .controlSize(.small)
        .disabled(pinInput.isEmpty)
    }

    private func appendDigit(_ digit: String) {
        guard pinInput.count < 4 else { return }
        pinInput.append(contentsOf: digit)
    }

    private func deleteDigit() {
        guard !pinInput.isEmpty else { return }
        pinInput.removeLast()
    }

    private func requiresPin(for user: PlexHomeUser) -> Bool {
        user.protected ?? false
    }

    private func borderColor(for user: PlexHomeUser) -> Color {
        if viewModel.activeUserUUID == user.uuid {
            return .brandPrimary
        }
        return .white.opacity(0.2)
    }

    private func resetPinPrompt() {
        pinPromptUser = nil
        pinInput = ""
    }
}
