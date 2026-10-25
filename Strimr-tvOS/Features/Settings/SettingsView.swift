import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(SessionManager.self) private var sessionManager
    @Environment(\.dismiss) private var dismiss
    @State private var navigation: SettingsNavigation
    @State private var focusCandidates: [SettingsFocusCandidate] = []
    @State private var scrollReadyPages: Set<String> = []
    @State private var previewedCategory: SettingsCategory?
    @State private var categoryPreviewTask: Task<Void, Never>?
    @State private var requestedDetailTarget: SettingsFocusTarget?
    @FocusedValue(\.settingsActualFocus) private var actualDetailFocus
    @FocusState private var focusedTarget: SettingsFocusTarget?

    /// The first category is known before the first frame, so neither the selection nor the detail page jumps.
    init(canManageAccounts: Bool) {
        let category = SettingsCategory.visible(canManageAccounts: canManageAccounts).first ?? .playback
        _navigation = State(initialValue: SettingsNavigation(category: category))
    }

    var body: some View {
        GeometryReader { geometry in
            HStack(alignment: .top, spacing: 36) {
                SettingsSidebar(
                    categories: visibleCategories,
                    selectedCategory: previewedCategory ?? navigation.category,
                    focusedTarget: $focusedTarget,
                )
                .frame(width: (geometry.size.width - 73) * 0.32)

                Rectangle()
                    .fill(.strokeSubtle)
                    .frame(width: 1)
                    .overlay {
                        switch focusedTarget {
                        case .category, .detailEntry:
                            focusGate(.detailEntry)
                        case .control, .back, .sidebarEntry:
                            focusGate(.sidebarEntry)
                        case nil:
                            EmptyView()
                        }
                    }

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
        .defaultFocus($focusedTarget, .category(navigation.category))
        .onChange(of: focusedTarget) { previous, target in
            switch target {
            case let .category(category):
                // Ignore a transient native fallback while the new detail page mounts.
                guard navigation.pendingDetailFocus == nil else { return }
                // Entering from the tab bar lands on the geometrically closest row; restore the selection.
                if previous == nil, category != navigation.category {
                    focusedTarget = .category(navigation.category)
                    return
                }
                navigation.sidebarFocused = true
                previewCategory(category)
            case .control:
                // FocusState also changes when a request is issued; it is not an acknowledgement.
                break
            case .detailEntry:
                commitPreviewedCategory()
                navigation.enterDetailFromSidebar()
            case .sidebarEntry:
                navigation.enterSidebar()
            case .back:
                navigation.sidebarFocused = false
            case nil:
                break
            }
        }
        .onChange(of: actualDetailFocus) { _, target in
            guard case let .control(pageID, id) = target, pageID == navigation.pageID else { return }
            if navigation.pendingDetailFocus != nil {
                guard target == requestedDetailTarget else { return }
                navigation.pendingDetailFocus = nil
            }
            navigation.focusedControls[pageID] = id
            navigation.sidebarFocused = false
        }
        .onPreferenceChange(SettingsScrollReadyKey.self) { pages in
            scrollReadyPages = pages
            fulfillDetailFocusRequest()
        }
        .onPreferenceChange(SettingsFocusCandidatesKey.self) { candidates in
            focusCandidates = candidates
            fulfillDetailFocusRequest()
        }
        .onChange(of: navigation.detailRequest) { _, _ in
            requestedDetailTarget = nil
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

    /// Building a detail page is expensive; skip the pages the focus only passes through.
    private func previewCategory(_ category: SettingsCategory) {
        categoryPreviewTask?.cancel()
        guard category != navigation.category else {
            previewedCategory = nil
            return
        }
        previewedCategory = category
        categoryPreviewTask = Task {
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            commitPreviewedCategory()
        }
    }

    private func commitPreviewedCategory() {
        categoryPreviewTask?.cancel()
        categoryPreviewTask = nil
        guard let previewedCategory else { return }
        self.previewedCategory = nil
        navigation.category = previewedCategory
    }

    /// One focus binding owns both columns. Wait for the destination's enabled controls
    /// to enter the view tree instead of racing per-row bindings against resetFocus.
    private func fulfillDetailFocusRequest() {
        guard let pageID = navigation.pendingDetailFocus, scrollReadyPages.contains(pageID) else { return }
        let candidates = focusCandidates.filter { $0.pageID == pageID }
        guard let candidate = candidates.first(where: { $0.id == navigation.focusedControls[pageID] })
            ?? candidates.first(where: \.isDefault)
            ?? candidates.first, requestedDetailTarget != candidate.target else { return }
        requestedDetailTarget = candidate.target
        focusedTarget = candidate.target
        if actualDetailFocus == candidate.target {
            navigation.pendingDetailFocus = nil
            navigation.sidebarFocused = false
        }
    }

    /// Crossing the divider would otherwise land on the geometrically closest row or control,
    /// visibly, and in the sidebar that would also change the selected category.
    private func focusGate(_ target: SettingsFocusTarget) -> some View {
        Color.clear
            .frame(width: 2)
            .frame(maxHeight: .infinity)
            .focusable()
            .focusEffectDisabled()
            .focused($focusedTarget, equals: target)
            .accessibilityHidden(true)
    }

    private var visibleCategories: [SettingsCategory] {
        SettingsCategory.visible(canManageAccounts: sessionManager.canManageAccounts)
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
                                    .font(.cardMetadata)
                                Text(page.title)
                            }
                        }
                        .font(.facts)
                        .foregroundStyle(.textSecondary)
                        .lineLimit(1)
                    }
                    Text(navigation.currentPages.last?.title ?? navigation.category.title)
                        .font(.tileTitle)
                        .foregroundStyle(.textPrimary)
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
        case .accounts: TVAccountsSettingsView()
        case .profiles: TVProfilesSettingsView()
        case .playback: SettingsPlaybackView()
        case .audio: SettingsAudioView()
        case .subtitles: SettingsSubtitlesView()
        case .interface:
            SettingsInterfaceView(settingsManager: settingsManager, libraryStore: libraryStore)
        case .integrations: IntegrationsView()
        case .privacy: SettingsPrivacyView()
        case .about: SettingsAboutView()
        }
    }
}

/// A separate view so preference and focus-request updates of the detail column do not rebuild it.
private struct SettingsSidebar: View {
    @Environment(SettingsNavigation.self) private var navigation
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let categories: [SettingsCategory]
    /// Leads the debounced detail page so the previous selection does not linger behind the focus.
    let selectedCategory: SettingsCategory
    let focusedTarget: FocusState<SettingsFocusTarget?>.Binding

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            Text("settings.title")
                .font(.heroTitle)
                .foregroundStyle(.textPrimary)
                .padding(.leading, 20)

            VStack(spacing: 16) {
                ForEach(categories) { category in
                    Button {
                        navigation.category = category
                        navigation.enterDetailFromSidebar()
                    } label: {
                        HStack(spacing: 18) {
                            Image(systemName: category.symbol)
                                .frame(width: 32)
                            Text(category.title)
                                .font(.rowTitle)
                            Spacer(minLength: 0)
                        }
                    }
                    .buttonStyle(SettingsCategoryButtonStyle(isSelected: selectedCategory == category))
                    .focusEffectDisabled()
                    .focused(focusedTarget, equals: .category(category))
                    .accessibilityAddTraits(selectedCategory == category ? .isSelected : [])
                }
            }
            Spacer(minLength: 0)
        }
        .focusSection()
        .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: selectedCategory)
    }
}

/// The sidebar draws its own focus surface; avoid the native button background and scale.
private struct SettingsCategoryButtonStyle: ButtonStyle {
    let isSelected: Bool

    func makeBody(configuration: Configuration) -> some View {
        SettingsCategoryRow(label: configuration.label, isSelected: isSelected)
            .opacity(configuration.isPressed ? 0.7 : 1)
    }
}

/// Follows the native focus directly: FocusState only updates after the move and made the highlight trail behind.
private struct SettingsCategoryRow<Label: View>: View {
    @Environment(\.isFocused) private var isFocused
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let label: Label
    let isSelected: Bool

    var body: some View {
        label
            .foregroundStyle(isFocused ? Color.black : Color.primary)
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .background {
                RoundedRectangle(cornerRadius: LayoutMetrics.cardCornerRadius, style: .continuous)
                    .fill(isFocused ? Color.white : isSelected ? Color.selectionAccent.opacity(0.18) : .clear)
            }
            .overlay(alignment: .leading) {
                if isSelected {
                    Capsule()
                        .fill(Color.selectionAccent)
                        .frame(width: 4, height: 28)
                }
            }
            .animation(Motion.animation(Motion.focus, reduceMotion: reduceMotion), value: isFocused)
    }
}
