import SwiftUI

struct ProfileSwitcherView: View {
    @State private var viewModel: ProfileSwitcherViewModel
    @State private var isShowingProfiles = false
    /// Scrolls to the profile picked with the arrows; hovering must not scroll.
    @State private var keyboardHighlightID: String?
    @FocusState private var isKeyboardFocused: Bool
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
        .toolbarBackgroundVisibility(.hidden, for: .windowToolbar)
        .focusable()
        .focusEffectDisabled()
        .focused($isKeyboardFocused)
        .onKeyPress(action: handleKey)
        .onAppear { isKeyboardFocused = true }
        .task { await viewModel.load() }
        .sheet(isPresented: $isShowingProfiles, onDismiss: refreshAfterSheet) {
            NavigationStack { ProfilesSettingsView() }
                .frame(minWidth: 520, minHeight: 480)
        }
        .sheet(item: $viewModel.profileNeedingConnection, onDismiss: refreshAfterSheet) { profile in
            NavigationStack { ProfileDetailView(profileID: profile.id, startsWithNewConnection: true) }
                .frame(minWidth: 520, minHeight: 480)
        }
    }

    private var picker: some View {
        GeometryReader { geometry in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(spacing: 48) {
                        Text("auth.profile.header.title")
                            .font(.heroTitle)
                            .foregroundStyle(.textPrimary)

                        if let error = viewModel.errorMessage {
                            errorBanner(error)
                        }

                        profiles
                    }
                    .padding(.horizontal, 48)
                    .padding(.vertical, 64)
                    .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                }
                .scrollBounceBehavior(.basedOnSize)
                .onChange(of: keyboardHighlightID) { _, id in
                    guard let id else { return }
                    withAnimation { proxy.scrollTo(id, anchor: .center) }
                }
            }
        }
        .overlay(alignment: .topTrailing) {
            HStack(spacing: 12) {
                if viewModel.canManageProfiles {
                    Button("profiles.manage", systemImage: "pencil") { isShowingProfiles = true }
                }
                if viewModel.canCancel {
                    Button("common.actions.cancel") { viewModel.cancel() }
                        .keyboardShortcut(.cancelAction)
                }
            }
            .padding(20)
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
                    .foregroundStyle(.textSecondary)
            }
        } else {
            CenteredFlowLayout(spacing: ProfilePickerMetrics.itemSpacing, lineSpacing: 36) {
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(viewModel.switchingID != nil)
        .id(choice.id)
        .onHover { isHovering in
            if isHovering {
                viewModel.highlightedID = choice.id
            }
        }
    }

    private func pinStage(for choice: ProfileChoice) -> some View {
        PINEntryPad(
            title: choice.name,
            message: viewModel.errorMessage ?? String(localized: "auth.profile.pin.prompt \(choice.name)"),
            pinCount: viewModel.pin.count,
            rejectedCount: viewModel.rejectedPINCount,
            isDisabled: viewModel.switchingID != nil,
            onDigit: viewModel.appendPINDigit,
            onDelete: viewModel.deletePINDigit,
        ) {
            ProfileAvatarView(
                choice: choice,
                size: ProfilePickerMetrics.entranceAvatarSize,
                isSwitching: viewModel.switchingID == choice.id,
                showsBadges: false,
                namespace: namespace,
            )
        } footer: {
            Button("common.actions.cancel", action: viewModel.cancelPIN)
                .disabled(viewModel.switchingID != nil)
        }
        .transition(.opacity)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(spacing: 16) {
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.textPrimary)
            Button("common.actions.retry") {
                Task { await viewModel.load() }
            }
        }
        .padding(16)
        .glassSurface(in: RoundedRectangle(cornerRadius: LayoutMetrics.overlayCornerRadius, style: .continuous))
    }

    private func handleKey(_ press: KeyPress) -> KeyPress.Result {
        if viewModel.pinChoice != nil {
            switch press.key {
            case .escape:
                viewModel.cancelPIN()
            case .delete:
                viewModel.deletePINDigit()
            default:
                guard let digit = press.characters.first, press.characters.count == 1, digit.isASCII,
                      digit.isNumber
                else { return .ignored }
                viewModel.appendPINDigit(String(digit))
            }
            return .handled
        }

        switch press.key {
        case .leftArrow:
            moveHighlight(by: -1)
        case .rightArrow:
            moveHighlight(by: 1)
        case .return, .space:
            guard let choice = viewModel.choices.first(where: { $0.id == viewModel.highlightedID }) else {
                return .ignored
            }
            viewModel.choose(choice)
        default:
            return .ignored
        }
        return .handled
    }

    private func moveHighlight(by offset: Int) {
        let choices = viewModel.choices
        guard !choices.isEmpty else { return }
        let current = choices.firstIndex { $0.id == viewModel.highlightedID }
        let next = current.map { ($0 + offset + choices.count) % choices.count } ?? 0
        viewModel.highlightedID = choices[next].id
        keyboardHighlightID = choices[next].id
    }

    private func refreshAfterSheet() {
        viewModel.refreshChoices()
        isKeyboardFocused = true
    }
}
