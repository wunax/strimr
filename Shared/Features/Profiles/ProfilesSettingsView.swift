import SwiftUI

/// Profiles of the app: local profiles and Plex Home users, with the option to ask for the profile at launch.
struct ProfilesSettingsView: View {
    @Environment(SessionManager.self) private var sessionManager
    @State private var isCreatingProfile = false
    @State private var createdProfileID: String?

    var body: some View {
        List {
            Section {
                ForEach(sessionManager.profiles) { profile in
                    NavigationLink {
                        ProfileDetailView(profileID: profile.id)
                    } label: {
                        ProfileRow(profile: profile, isActive: profile.id == sessionManager.activeProfile?.id)
                    }
                }
            }

            Section {
                Button { isCreatingProfile = true } label: {
                    Label("profiles.create", systemImage: "plus.circle")
                }
                .foregroundStyle(.primary)
            }

            if sessionManager.profiles.count > 1 {
                Section {
                    Toggle("profiles.askOnLaunch", isOn: Binding(
                        get: { sessionManager.profileStore.asksProfileOnLaunch },
                        set: { sessionManager.setAsksProfileOnLaunch($0) },
                    ))
                } footer: {
                    Text("profiles.askOnLaunch.footer")
                }
            }
        }
        .taskModalTitle("profiles.title")
        .taskPresentation(isPresented: $isCreatingProfile) {
            CreateLocalProfileView(
                onCreate: { profile in
                    isCreatingProfile = false
                    createdProfileID = profile.id
                },
                onCancel: { isCreatingProfile = false },
            )
        }
        .navigationDestination(item: $createdProfileID) { profileID in
            // A new local profile goes straight to "Add a connection": without one it cannot be activated.
            ProfileDetailView(profileID: profileID, startsWithNewConnection: true)
        }
    }
}

/// Name and optional PIN of a new local profile.
struct CreateLocalProfileView: View {
    @Environment(SessionManager.self) private var sessionManager
    let onCreate: (LocalProfile) -> Void
    let onCancel: () -> Void
    @State private var name = ""
    @State private var pin = ""

    var body: some View {
        TaskModalNavigationView {
            Form {
                TextField("profiles.name", text: $name)
                SecureField("profiles.pin.optional", text: $pin)
                #if os(iOS)
                    .keyboardType(.numberPad)
                #endif
                #if os(tvOS)
                    Button("common.actions.continue", action: create)
                        .disabled(isNameEmpty)
                #endif
            }
            .taskModalTitle("profiles.create")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel", action: onCancel)
                }
                #if !os(tvOS)
                    ToolbarItem(placement: .confirmationAction) {
                        Button("common.actions.continue", action: create)
                            .disabled(isNameEmpty)
                    }
                #endif
            }
        }
    }

    private var isNameEmpty: Bool {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func create() {
        onCreate(sessionManager.createLocalProfile(name: name, pin: String(pin.filter(\.isNumber).prefix(4))))
    }
}

struct ProfileRow: View {
    let profile: StrimrProfile
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            avatar
                .frame(width: 40, height: 40)
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            VStack(alignment: .leading, spacing: 2) {
                Text(profile.name)
                Text(profile.isLocal ? "profiles.kind.local" : "profiles.kind.plexHome")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if isActive {
                Image(systemName: "checkmark")
                    .foregroundStyle(.brandPrimary)
            }
        }
    }

    @ViewBuilder
    private var avatar: some View {
        switch profile {
        case let .local(local):
            ProfileInitialsAvatar(initials: ProfileChoice(
                id: local.id,
                name: local.name,
                detail: nil,
                avatarURL: nil,
                requiresPIN: false,
                isActive: false,
                isLocal: true,
            ).initials)
        case let .plexHome(home):
            AsyncImage(url: home.user.thumb) { image in
                image.resizable().scaledToFill()
            } placeholder: {
                Image(systemName: "person.crop.square.fill")
                    .resizable()
                    .foregroundStyle(.secondary)
            }
        }
    }
}
