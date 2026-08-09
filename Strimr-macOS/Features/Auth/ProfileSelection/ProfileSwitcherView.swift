import SwiftUI

struct ProfileSwitcherView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinUser: PlexHomeUser?
    @State private var pin = ""
    @State private var isShowingLogoutConfirmation = false

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 6) {
                    Text("auth.profile.header.title")
                        .font(.largeTitle.bold())
                    Text("auth.profile.header.subtitle")
                        .foregroundStyle(.secondary)
                }
                Spacer()
                Button("common.actions.logOut", systemImage: "rectangle.portrait.and.arrow.right", role: .destructive) {
                    isShowingLogoutConfirmation = true
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading, viewModel.users.isEmpty {
                ProgressView("auth.profile.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 24)], spacing: 24) {
                        ForEach(viewModel.users) { user in
                            profileButton(for: user)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(32)
        .task { await viewModel.loadUsers() }
        .alert("common.actions.logOut", isPresented: $isShowingLogoutConfirmation) {
            Button("common.actions.logOut", role: .destructive) {
                Task { await sessionManager.signOut() }
            }
            Button("common.actions.cancel", role: .cancel) {}
        } message: {
            Text("more.logout.message")
        }
        .sheet(item: $pinUser) { user in
            VStack(alignment: .leading, spacing: 16) {
                Text("auth.profile.pin.title").font(.headline)
                Text("auth.profile.pin.prompt \(user.friendlyName ?? user.title ?? "?")")
                    .foregroundStyle(.secondary)
                SecureField("auth.profile.pin.placeholder", text: $pin)
                    .frame(width: 240)
                    .onSubmit { submitPin(for: user) }
                HStack {
                    Button("common.actions.cancel", role: .cancel) {
                        pinUser = nil
                    }
                    Spacer()
                    Button("signIn.button.continue") {
                        submitPin(for: user)
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(pin.isEmpty)
                }
            }
            .padding(24)
            .frame(width: 360)
        }
    }

    private func profileButton(for user: PlexHomeUser) -> some View {
        Button {
            if user.protected == true {
                pin = ""
                pinUser = user
            } else {
                Task { await viewModel.switchToUser(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 10) {
                AsyncImage(url: user.thumb) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        Image(systemName: "person.crop.square.fill")
                            .resizable()
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if user.protected == true {
                        Image(systemName: "lock.fill").padding(8)
                    }
                }
                Text(user.friendlyName ?? user.title ?? "?")
                    .font(.headline)
                    .lineLimit(1)
                if viewModel.switchingUserUUID == user.uuid {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingUserUUID != nil)
    }

    private func submitPin(for user: PlexHomeUser) {
        let submittedPin = pin
        pinUser = nil
        pin = ""
        Task { await viewModel.switchToUser(user, pin: submittedPin) }
    }
}
