import SwiftUI

@MainActor
struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var isShowingProfiles = false
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
        .navigationBarTitleDisplayMode(.inline)
        .toolbarBackground(.hidden, for: .navigationBar)
        .toolbar {
            if viewModel.pinChoice != nil {
                ToolbarItem(placement: .cancellationAction) {
                    Button("common.actions.cancel") { viewModel.cancelPIN() }
                }
            } else {
                if viewModel.canCancel {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("common.actions.cancel") { viewModel.cancel() }
                    }
                }
                if viewModel.canManageProfiles {
                    ToolbarItem(placement: .topBarTrailing) {
                        Button("profiles.manage", systemImage: "pencil") { isShowingProfiles = true }
                    }
                }
            }
        }
        .sheet(isPresented: $isShowingProfiles, onDismiss: viewModel.refreshChoices) {
            NavigationStack { ProfilesSettingsView() }
        }
        .sheet(item: $viewModel.profileNeedingConnection, onDismiss: viewModel.refreshChoices) { profile in
            NavigationStack { ProfileDetailView(profileID: profile.id, startsWithNewConnection: true) }
        }
        .sensoryFeedback(.error, trigger: viewModel.rejectedPINCount)
        .task { await viewModel.load() }
    }

    private var picker: some View {
        GeometryReader { geometry in
            ScrollView {
                VStack(spacing: 40) {
                    Text("auth.profile.header.title")
                        .font(.largeTitle.bold())
                        .foregroundStyle(.white)
                        .multilineTextAlignment(.center)

                    if let error = viewModel.errorMessage {
                        errorBanner(error)
                    }

                    profiles
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 32)
                .frame(maxWidth: .infinity, minHeight: geometry.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
            .refreshable { await viewModel.load() }
        }
        .transition(.opacity)
    }

    @ViewBuilder
    private var profiles: some View {
        if viewModel.choices.isEmpty {
            if viewModel.isLoading {
                ProgressView("auth.profile.loading")
                    .tint(.white)
            } else {
                Text("auth.profile.empty")
                    .foregroundStyle(.white.opacity(0.7))
            }
        } else {
            CenteredFlowLayout(spacing: ProfilePickerMetrics.itemSpacing, lineSpacing: 32) {
                ForEach(viewModel.choices) { choice in
                    profileButton(for: choice)
                }
            }
        }
    }

    private func profileButton(for choice: ProfileChoice) -> some View {
        let isHighlighted = viewModel.highlightedID == choice.id
        return Button {
            viewModel.choose(choice)
        } label: {
            VStack(spacing: 14) {
                ProfileAvatarView(
                    choice: choice,
                    isHighlighted: isHighlighted,
                    isSwitching: viewModel.switchingID == choice.id,
                    namespace: namespace,
                )
                ProfileNameLabel(choice: choice, isHighlighted: isHighlighted)
            }
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingID != nil)
    }

    private func pinStage(for choice: ProfileChoice) -> some View {
        ScrollView {
            VStack(spacing: 28) {
                ProfileAvatarView(
                    choice: choice,
                    isSwitching: viewModel.switchingID == choice.id,
                    showsBadges: false,
                    namespace: namespace,
                )
                VStack(spacing: 8) {
                    Text(choice.name)
                        .font(.title2.bold())
                    Text(viewModel.errorMessage ?? String(localized: "auth.profile.pin.prompt \(choice.name)"))
                        .foregroundStyle(.white.opacity(0.7))
                        .multilineTextAlignment(.center)
                }
                .foregroundStyle(.white)

                PINDotsView(count: viewModel.pin.count)
                    .shake(viewModel.rejectedPINCount)

                ProfileKeypad(
                    canDelete: !viewModel.pin.isEmpty,
                    onDigit: viewModel.appendPINDigit,
                    onDelete: viewModel.deletePINDigit,
                )
                .disabled(viewModel.switchingID != nil)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 24)
            .frame(maxWidth: .infinity)
        }
        .scrollBounceBehavior(.basedOnSize)
        .transition(.opacity)
    }

    private func errorBanner(_ message: String) -> some View {
        VStack(spacing: 12) {
            Text(message)
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
            Button("common.actions.retry", systemImage: "arrow.clockwise") {
                Task { await viewModel.load() }
            }
            .fontWeight(.semibold)
            .foregroundStyle(.white)
        }
        .padding(20)
        .frame(maxWidth: 420)
        .profileGlass(in: RoundedRectangle(cornerRadius: 24, style: .continuous))
    }
}
