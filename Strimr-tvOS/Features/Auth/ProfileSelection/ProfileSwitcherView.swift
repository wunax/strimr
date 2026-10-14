import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var isShowingProfiles = false
    @FocusState private var focusedUserID: String?
    @Namespace private var namespace

    init(viewModel: ProfileSwitcherViewModel) {
        _viewModel = State(initialValue: viewModel)
    }

    var body: some View {
        ZStack {
            ProfilePickerBackground(tint: viewModel.tint)

            if let entering = viewModel.enteringChoice {
                ProfileEntranceView(choice: entering, namespace: namespace)
            } else if let pinChoice = viewModel.pinChoice {
                pinStage(for: pinChoice)
            } else {
                picker
            }
        }
        .animation(ProfilePickerMetrics.entranceAnimation, value: viewModel.enteringID)
        .animation(ProfilePickerMetrics.entranceAnimation, value: viewModel.pinChoice)
        .environment(\.colorScheme, .dark)
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
        .onChange(of: focusedUserID) { _, id in
            if let id {
                viewModel.highlightedID = id
            }
        }
        .onChange(of: viewModel.choices, initial: true) { _, choices in
            guard focusedUserID == nil else { return }
            focusedUserID = (choices.first(where: \.isActive) ?? choices.first)?.id
        }
        .onChange(of: viewModel.pinChoice) { _, choice in
            if choice == nil {
                focusedUserID = viewModel.highlightedID
            }
        }
    }

    private var picker: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 72) {
                    Text("auth.profile.header.title")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    profiles
                }
                .padding(80)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollClipDisabled()
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 24) {
                if viewModel.canManageProfiles {
                    Button("profiles.manage", systemImage: "pencil") { isShowingProfiles = true }
                }
                if viewModel.canCancel {
                    Button("common.actions.cancel") { viewModel.cancel() }
                }
            }
            .padding(48)
            .focusSection()
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var profiles: some View {
        if viewModel.choices.isEmpty {
            if viewModel.isLoading {
                ProgressView("auth.profile.loading")
            } else {
                Text("auth.profile.empty")
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            CenteredFlowLayout(spacing: ProfilePickerMetrics.itemSpacing, lineSpacing: 56) {
                ForEach(viewModel.choices) { choice in
                    profileButton(for: choice)
                }
            }
            .focusSection()
        }
    }

    private func profileButton(for choice: ProfileChoice) -> some View {
        let isFocused = focusedUserID == choice.id
        return Button {
            viewModel.choose(choice)
        } label: {
            VStack(spacing: 28) {
                ProfileAvatarView(
                    choice: choice,
                    isHighlighted: isFocused,
                    isSwitching: viewModel.switchingID == choice.id,
                    namespace: namespace,
                )
                ProfileNameLabel(choice: choice, isHighlighted: isFocused)
            }
        }
        .buttonStyle(ProfileFocusButtonStyle())
        .focused($focusedUserID, equals: choice.id)
    }

    private func pinStage(for choice: ProfileChoice) -> some View {
        HStack(spacing: 160) {
            VStack(spacing: 40) {
                ProfileAvatarView(
                    choice: choice,
                    size: ProfilePickerMetrics.entranceAvatarSize,
                    isSwitching: viewModel.switchingID == choice.id,
                    showsBadges: false,
                    namespace: namespace,
                )
                VStack(spacing: 12) {
                    Text(choice.name)
                        .font(.title2.bold())
                    Text(viewModel.errorMessage ?? String(localized: "auth.profile.pin.prompt \(choice.name)"))
                        .font(.callout)
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)
                .frame(maxWidth: 560)

                PINDotsView(count: viewModel.pin.count)
                    .shake(viewModel.rejectedPINCount)
            }

            ProfileKeypad(
                canDelete: !viewModel.pin.isEmpty,
                onDigit: viewModel.appendPINDigit,
                onDelete: viewModel.deletePINDigit,
            )
            .disabled(viewModel.switchingID != nil)
            .focusSection()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onExitCommand(perform: viewModel.cancelPIN)
        .transition(.opacity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 32) {
            Text(message)
                .foregroundStyle(.white)
            Button("common.actions.retry", systemImage: "arrow.clockwise") {
                Task { await viewModel.load() }
            }
        }
        .padding(28)
        .profileGlass(in: RoundedRectangle(cornerRadius: 32, style: .continuous))
        .focusSection()
    }
}

/// The avatar draws its own focus state; the system lift would square it.
private struct ProfileFocusButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.spring(duration: 0.2), value: configuration.isPressed)
    }
}
