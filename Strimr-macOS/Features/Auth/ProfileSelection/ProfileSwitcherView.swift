import SwiftUI

struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var pinUser: ProfileChoice?
    @State private var pin = ""
    @State private var isShowingProfiles = false

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
                if viewModel.canManageProfiles {
                    Button("profiles.manage") { isShowingProfiles = true }
                }
                if viewModel.canCancel {
                    Button("common.actions.cancel") { viewModel.cancel() }
                }
            }

            if let errorMessage = viewModel.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            }

            if viewModel.isLoading, viewModel.choices.isEmpty {
                ProgressView("auth.profile.loading")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 150), spacing: 24)], spacing: 24) {
                        ForEach(viewModel.choices) { user in
                            profileButton(for: user)
                        }
                    }
                    .padding(4)
                }
            }
        }
        .padding(32)
        .task { await viewModel.load() }
        .sheet(isPresented: $isShowingProfiles, onDismiss: viewModel.refreshChoices) {
            NavigationStack { ProfilesSettingsView() }
                .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(item: $viewModel.profileNeedingConnection, onDismiss: viewModel.refreshChoices) { profile in
            NavigationStack { ProfileDetailView(profileID: profile.id, startsWithNewConnection: true) }
                .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(item: $pinUser) { user in
            VStack(alignment: .leading, spacing: 16) {
                Text("auth.profile.pin.title").font(.headline)
                Text("auth.profile.pin.prompt \(user.name)")
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

    private func profileButton(for user: ProfileChoice) -> some View {
        Button {
            if user.requiresPIN {
                pin = ""
                pinUser = user
            } else {
                Task { await viewModel.select(user, pin: nil) }
            }
        } label: {
            VStack(spacing: 10) {
                Group {
                    if user.isLocal {
                        ProfileInitialsAvatar(initials: user.initials)
                    } else {
                        AsyncImage(url: user.avatarURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFill()
                            } else {
                                Image(systemName: "person.crop.square.fill")
                                    .resizable()
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(width: 132, height: 132)
                .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                .overlay(alignment: .topTrailing) {
                    if user.requiresPIN {
                        Image(systemName: "lock.fill").padding(8)
                    } else if user.isActive {
                        Image(systemName: "checkmark.circle.fill").padding(8)
                    }
                }
                Text(user.name)
                    .font(.headline)
                    .lineLimit(1)
                if viewModel.switchingID == user.id {
                    ProgressView().controlSize(.small)
                }
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingID != nil)
    }

    private func submitPin(for user: ProfileChoice) {
        let submittedPin = pin
        pinUser = nil
        pin = ""
        Task { await viewModel.select(user, pin: submittedPin) }
    }
}
