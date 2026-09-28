import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation = SettingsNavigation()
    @State private var focusCandidates: [SettingsFocusCandidate] = []
    @State private var didSetInitialFocus = false
    @FocusState private var focusedTarget: SettingsFocusTarget?

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 36) {
                sidebar
                    .frame(width: (geometry.size.width - 73) * 0.32)

                Rectangle()
                    .fill(.white.opacity(0.1))
                    .frame(width: 1)

                detail
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .padding(.horizontal, 48)
        .padding(.vertical, 32)
        .background(Color("Background").ignoresSafeArea())
        .toolbar(.hidden, for: .navigationBar)
        .environment(navigation)
        .environment(\.settingsFocusBinding, $focusedTarget)
        .onAppear {
            guard !didSetInitialFocus else { return }
            didSetInitialFocus = true
            focusedTarget = .category(navigation.category)
        }
        .onChange(of: focusedTarget) { _, target in
            switch target {
            case let .category(category):
                // Ignore a transient native fallback while the new detail page mounts.
                guard navigation.pendingDetailFocus == nil else { return }
                navigation.sidebarFocused = true
                navigation.category = category
            case let .control(pageID, id):
                guard pageID == navigation.pageID else { return }
                navigation.focusedControls[pageID] = id
                navigation.pendingDetailFocus = nil
                navigation.sidebarFocused = false
            case .back:
                navigation.sidebarFocused = false
            case nil:
                break
            }
        }
        .onPreferenceChange(SettingsFocusCandidatesKey.self) { candidates in
            focusCandidates = candidates
            fulfillDetailFocusRequest()
        }
        .onChange(of: navigation.detailRequest) { _, _ in
            fulfillDetailFocusRequest()
        }
        .onChange(of: navigation.sidebarRequest) { _, _ in
            focusedTarget = .category(navigation.category)
        }
        .onExitCommand {
            if navigation.sidebarFocused {
                dismiss()
            } else if !navigation.currentPages.isEmpty {
                navigation.pop()
            } else {
                navigation.enterSidebar()
            }
        }
    }

    /// One focus binding owns both columns. Wait for the destination's enabled controls
    /// to enter the view tree instead of racing per-row bindings against resetFocus.
    private func fulfillDetailFocusRequest() {
        guard let pageID = navigation.pendingDetailFocus else { return }
        let candidates = focusCandidates.filter { $0.pageID == pageID }
        guard let candidate = candidates.first(where: { $0.id == navigation.focusedControls[pageID] })
            ?? candidates.first(where: \.isDefault)
            ?? candidates.first else { return }
        focusedTarget = candidate.target
        navigation.focusedControls[pageID] = candidate.id
        navigation.pendingDetailFocus = nil
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("settings.title")
                .font(.largeTitle.bold())
                .padding(.leading, 20)

            VStack(spacing: 16) {
                ForEach(SettingsCategory.allCases) { category in
                    Button {
                        navigation.category = category
                        navigation.enterDetail()
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: category.symbol)
                                .frame(width: 32)
                            Text(category.title)
                                .font(.headline)
                            Spacer(minLength: 0)
                        }
                        .foregroundStyle(focusedTarget == .category(category) ? Color.black : Color.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    focusedTarget == .category(category) ? Color.white :
                                        navigation.category == category ? Color.brandPrimary.opacity(0.18) : .clear,
                                )
                        }
                        .overlay(alignment: .leading) {
                            if navigation.category == category {
                                Capsule()
                                    .fill(Color.brandPrimary)
                                    .frame(width: 4, height: 28)
                            }
                        }
                    }
                    .buttonStyle(SettingsCategoryButtonStyle())
                    .focusEffectDisabled()
                    .focused($focusedTarget, equals: .category(category))
                    .accessibilityAddTraits(navigation.category == category ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .focusSection()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: navigation.category)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: focusedTarget)
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                if !navigation.currentPages.isEmpty {
                    Button {
                        navigation.pop()
                    } label: {
                        Image(systemName: "chevron.left")
                    }
                    .accessibilityLabel(Text("settings.navigation.back"))
                    .focused($focusedTarget, equals: .back)
                    .onMoveCommand { direction in
                        if direction == .left {
                            navigation.enterSidebar()
                        }
                    }
                }
                VStack(alignment: .leading, spacing: 8) {
                    if !navigation.currentPages.isEmpty {
                        HStack(spacing: 10) {
                            Text(navigation.category.title)
                            ForEach(navigation.currentPages.dropLast()) { page in
                                Image(systemName: "chevron.right")
                                    .font(.caption2)
                                Text(page.title)
                            }
                        }
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                    }
                    Text(navigation.currentPages.last?.title ?? navigation.category.title)
                        .font(.title2.bold())
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 20)
            .frame(minHeight: 80, alignment: .leading)

            SettingsDetailPage(pageID: navigation.pageID) {
                if let page = navigation.currentPages.last {
                    page.content
                } else {
                    categoryContent(navigation.category)
                }
            }
            .id(navigation.pageID)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .focusSection()
    }

    @ViewBuilder
    private func categoryContent(_ category: SettingsCategory) -> some View {
        switch category {
        case .playback: SettingsPlaybackView()
        case .audio: SettingsAudioView()
        case .subtitles: SettingsSubtitlesView()
        case .interface:
            SettingsInterfaceView(settingsManager: settingsManager, libraryStore: libraryStore)
        case .integrations: IntegrationsView()
        }
    }
}

/// The sidebar draws its own focus surface; avoid the native button background and scale.
private struct SettingsCategoryButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label.opacity(configuration.isPressed ? 0.7 : 1)
    }
}
