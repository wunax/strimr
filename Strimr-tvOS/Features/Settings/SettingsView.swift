import SwiftUI

@MainActor
struct SettingsView: View {
    @Environment(SettingsManager.self) private var settingsManager
    @Environment(LibraryStore.self) private var libraryStore
    @Environment(\.dismiss) private var dismiss
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var navigation = SettingsNavigation()
    @State private var visitedCategories: Set<SettingsCategory> = [.playback]
    @FocusState private var backFocused: Bool
    @FocusState private var focusedCategory: SettingsCategory?

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
        .onAppear { focusedCategory = navigation.category }
        .onChange(of: focusedCategory) { _, category in
            guard let category else { return }
            navigation.sidebarFocused = true
            visitedCategories.insert(category)
            navigation.category = category
        }
        .onChange(of: navigation.sidebarRequest) { _, _ in
            focusedCategory = navigation.category
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
                        .foregroundStyle(focusedCategory == category ? Color.black : Color.primary)
                        .padding(.horizontal, 20)
                        .padding(.vertical, 22)
                        .background {
                            RoundedRectangle(cornerRadius: 16)
                                .fill(
                                    focusedCategory == category ? Color.white :
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
                    .buttonStyle(.plain)
                    .focused($focusedCategory, equals: category)
                    .accessibilityAddTraits(navigation.category == category ? .isSelected : [])
                    .onMoveCommand { direction in
                        if direction == .right {
                            navigation.enterDetail()
                        }
                    }
                }
            }
            Spacer(minLength: 0)
        }
        .focusSection()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: navigation.category)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.16), value: focusedCategory)
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
                    .focused($backFocused)
                    .onChange(of: backFocused) { _, focused in
                        if focused {
                            navigation.sidebarFocused = false
                        }
                    }
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

            ZStack {
                ForEach(SettingsCategory.allCases.filter { visitedCategories.contains($0) }) { category in
                    SettingsDetailPage(
                        pageID: category.rawValue,
                        active: navigation.category == category && navigation.currentPages.isEmpty,
                    ) {
                        categoryContent(category)
                    }
                    ForEach(navigation.pages[category, default: []]) { page in
                        SettingsDetailPage(
                            pageID: page.id.uuidString,
                            active: navigation.category == category && navigation.currentPages.last?.id == page.id,
                        ) {
                            page.content
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
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
