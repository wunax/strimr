import SwiftUI

@MainActor
struct HomeRowsSettingsView: View {
    @State private var viewModel: HomeViewModel
    #if os(tvOS)
        @Environment(SettingsNavigation.self) private var navigation
    #endif

    init(sessionManager: SessionManager, settingsManager: SettingsManager) {
        _viewModel = State(initialValue: HomeViewModel(
            sessionManager: sessionManager,
            settingsManager: settingsManager,
        ))
    }

    var body: some View {
        settingsContainer
            .task {
                await viewModel.load()
                await viewModel.loadCatalog()
            }
            .refreshable {
                await viewModel.reload()
                await viewModel.loadCatalog()
            }
    }

    @ViewBuilder
    private var settingsContainer: some View {
        #if os(tvOS)
            SettingsList { sections }
        #else
            List { sections }
                .listStyle(homeRowsListStyle)
                .navigationTitle("settings.interface.homeRows.title")
        #endif
    }

    @ViewBuilder
    private var sections: some View {
        Section {
            Text("settings.interface.homeRows.description")
                .foregroundStyle(.secondary)
        }

        let shownRows = viewModel.shownRowsForEditing
        Section {
            if viewModel.isLoading, viewModel.availableRows.isEmpty {
                ProgressView("home.loading")
                    .frame(maxWidth: .infinity)
            } else if let errorMessage = viewModel.errorMessage, viewModel.availableRows.isEmpty {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .foregroundStyle(.red)
            } else if shownRows.isEmpty {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(Array(shownRows.enumerated()), id: \.element.id) { index, row in
                    shownRowControls(at: index, row: row, count: shownRows.count)
                }
            }
        } header: {
            Text("settings.interface.homeRows.section")
        }

        rowGroupSections

        Section {
            Button("settings.interface.homeRows.restoreDefaults", role: .destructive) {
                viewModel.resetRowPreferences()
            }
            #if os(tvOS)
            .settingsFocus("restoreRows", isDefault: shownRows.isEmpty)
            #endif
        }
    }

    // MARK: - Shown rows

    @ViewBuilder
    private func shownRowControls(at index: Int, row: HomeRow, count: Int) -> some View {
        #if os(tvOS)
            HStack(spacing: 24) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.title)
                        .font(.rowTitle)
                    rowSubtitle(for: row)
                }
                .frame(maxWidth: .infinity, alignment: .leading)

                HStack(spacing: 12) {
                    Button {
                        viewModel.setRowVisible(row.id, visible: false)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.hide", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .settingsFocus("row-\(row.id)-visibility", isDefault: index == 0)

                    Button {
                        viewModel.setRowStyle(otherStyle(than: viewModel.rowStyle(of: row)), of: row)
                    } label: {
                        viewModel.rowStyle(of: row).icon
                            .accessibilityLabel(Text("settings.interface.homeRows.style"))
                    }
                    .buttonStyle(.bordered)
                    .settingsFocus("row-\(row.id)-style", exitsLeft: false)

                    Button {
                        viewModel.moveRow(at: index, by: -1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveUp", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(index == 0 ? .tertiary : .secondary)
                    .settingsFocus("row-\(row.id)-up", exitsLeft: false)
                    .disabled(index == 0)

                    Button {
                        viewModel.moveRow(at: index, by: 1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveDown", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(index == count - 1 ? .tertiary : .secondary)
                    .settingsFocus("row-\(row.id)-down", exitsLeft: false)
                    .disabled(index == count - 1)
                }
                .fixedSize()
            }
        #else
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { true },
                    set: { viewModel.setRowVisible(row.id, visible: $0) },
                )) {
                    rowLabel(row)
                }

                styleMenu(for: row)

                Button {
                    viewModel.moveRow(at: index, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .foregroundStyle(index == 0 ? .tertiary : .secondary)
                .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                .disabled(index == 0)

                Button {
                    viewModel.moveRow(at: index, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .foregroundStyle(index == count - 1 ? .tertiary : .secondary)
                .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                .disabled(index == count - 1)
            }
            #if os(iOS)
            // Otherwise a tap anywhere on the List row triggers every button in it.
            // Borderless buttons no longer dim when disabled, hence the explicit tertiary style above.
            .buttonStyle(.borderless)
            #endif
        #endif
    }

    // MARK: - Libraries

    @ViewBuilder
    private var rowGroupSections: some View {
        #if os(macOS)
            ForEach(viewModel.rowGroups) { group in
                let hiddenRows = group.rows.filter { !viewModel.isRowVisible($0.id) }
                if !hiddenRows.isEmpty {
                    Section {
                        ForEach(hiddenRows) { row in
                            Toggle(row.title, isOn: Binding(
                                get: { false },
                                set: { viewModel.setRowVisible(row.id, visible: $0) },
                            ))
                        }
                    } header: {
                        HomeRowGroupTitle.text(for: group)
                    } footer: {
                        if group.isExcludedFromServerHome {
                            Text("settings.homeRows.excludedFromServerHome")
                        }
                    }
                }
            }
        #else
            let groups = viewModel.rowGroups
            if !groups.isEmpty {
                Section("settings.interface.homeRows.addRows") {
                    ForEach(groups) { group in
                        rowGroupLink(group)
                    }
                }
            }
        #endif
    }

    #if !os(macOS)
        @ViewBuilder
        private func rowGroupLink(_ group: HomeRowGroup) -> some View {
            #if os(tvOS)
                Button {
                    navigation.push(HomeRowGroupTitle.key(for: group)) {
                        HomeRowGroupSettingsView(viewModel: viewModel, groupID: group.id)
                    }
                } label: {
                    HStack(spacing: 20) {
                        rowGroupLabel(group)
                        Spacer(minLength: 16)
                        rowGroupCount(group)
                            .foregroundStyle(.secondary)
                        Image(systemName: "chevron.right")
                            .font(.cardMetadata.weight(.semibold))
                            .foregroundStyle(.secondary)
                    }
                }
                .settingsFocus("group-\(group.id)")
            #else
                NavigationLink {
                    HomeRowGroupSettingsView(viewModel: viewModel, groupID: group.id)
                } label: {
                    LabeledContent {
                        rowGroupCount(group)
                    } label: {
                        rowGroupLabel(group)
                    }
                }
            #endif
        }

        private func rowGroupLabel(_ group: HomeRowGroup) -> some View {
            VStack(alignment: .leading, spacing: 2) {
                Text(HomeRowGroupTitle.key(for: group))
                if let serverName = group.serverName {
                    Text("settings.homeRows.serverSubtitle \(serverName)")
                        .font(.cardMetadata)
                        .foregroundStyle(.secondary)
                }
            }
        }

        private func rowGroupCount(_ group: HomeRowGroup) -> Text {
            let shown = group.rows.count(where: { viewModel.isRowVisible($0.id) })
            return Text("settings.interface.homeRows.groupCount \(shown) \(group.rows.count)")
        }
    #endif

    // MARK: - Style

    #if os(tvOS)
        private func otherStyle(than style: HomeRowStyle) -> HomeRowStyle {
            style == .portrait ? .landscape : .portrait
        }
    #else
        private func styleMenu(for row: HomeRow) -> some View {
            let style = viewModel.rowStyle(of: row)
            return Menu {
                Picker(
                    "settings.interface.homeRows.style",
                    selection: Binding(
                        get: { style },
                        set: { viewModel.setRowStyle($0, of: row) },
                    ),
                ) {
                    ForEach([HomeRowStyle.portrait, .landscape], id: \.self) { option in
                        Label(option.title, systemImage: option.systemImage).tag(option)
                    }
                }
                .pickerStyle(.inline)
            } label: {
                style.icon
            }
            .menuIndicator(.hidden)
            .foregroundStyle(.secondary)
            .accessibilityLabel(Text("settings.interface.homeRows.style"))
            .accessibilityValue(Text(style.title))
        }
    #endif

    // MARK: - Helpers

    private func rowLabel(_ row: HomeRow) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(row.title)
            rowSubtitle(for: row)
        }
    }

    /// Tells apart rows sharing a title in different libraries or servers.
    @ViewBuilder
    private func rowSubtitle(for row: HomeRow) -> some View {
        if let subtitle = subtitle(for: row) {
            subtitle
                .font(.cardMetadata)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for row: HomeRow) -> Text? {
        let server = row.serverName.map { Text("settings.homeRows.serverSubtitle \($0)") }
        guard let libraryName = row.libraryName else { return server }
        guard let server else { return Text(verbatim: libraryName) }
        return Text(verbatim: "\(libraryName) · ") + server
    }

    #if os(tvOS)
        private func tvOSActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
            }
            .accessibilityLabel(Text(title))
        }
    #endif
}

private extension HomeRowStyle {
    var title: LocalizedStringKey {
        switch self {
        case .portrait: "settings.interface.homeRows.style.posters"
        case .landscape: "settings.interface.homeRows.style.thumbnails"
        }
    }

    var systemImage: String {
        switch self {
        case .portrait: "rectangle.portrait"
        case .landscape: "rectangle"
        }
    }

    /// Both symbols take the width of the wider one, so switching style does not shift the buttons beside it.
    var icon: some View {
        ZStack {
            Image(systemName: HomeRowStyle.landscape.systemImage)
                .hidden()
            Image(systemName: systemImage)
        }
    }
}

#if !os(tvOS)
    private var homeRowsListStyle: some ListStyle {
        #if os(macOS)
            .inset
        #else
            .insetGrouped
        #endif
    }
#endif

/// Every row of one library, turned on and off in place.
@MainActor
struct HomeRowGroupSettingsView: View {
    let viewModel: HomeViewModel
    let groupID: String

    var body: some View {
        let group = viewModel.rowGroups.first { $0.id == groupID }
        #if os(tvOS)
            SettingsList { section(group) }
        #else
            List { section(group) }
                .listStyle(homeRowsListStyle)
                .navigationTitle(group.map { Text(HomeRowGroupTitle.key(for: $0)) } ?? Text(verbatim: ""))
        #endif
    }

    private func section(_ group: HomeRowGroup?) -> some View {
        Section {
            if let group {
                ForEach(Array(group.rows.enumerated()), id: \.element.id) { index, row in
                    Toggle(row.title, isOn: Binding(
                        get: { viewModel.isRowVisible(row.id) },
                        set: { viewModel.setRowVisible(row.id, visible: $0) },
                    ))
                    #if os(tvOS)
                    .settingsFocus("row-\(row.id)", isDefault: index == 0)
                    #endif
                }
            } else {
                Text("common.empty.nothingToShow")
                    .foregroundStyle(.secondary)
            }
        } header: {
            if let serverName = group?.serverName {
                Text("settings.homeRows.serverSubtitle \(serverName)")
            }
        } footer: {
            if group?.isExcludedFromServerHome == true {
                Text("settings.homeRows.excludedFromServerHome")
            }
        }
    }
}

private enum HomeRowGroupTitle {
    static func key(for group: HomeRowGroup) -> LocalizedStringKey {
        group.libraryName.map { LocalizedStringKey(stringLiteral: $0) }
            ?? "settings.interface.homeRows.otherRows"
    }

    static func text(for group: HomeRowGroup) -> Text {
        let server = group.serverName.map { Text("settings.homeRows.serverSubtitle \($0)") }
        guard let libraryName = group.libraryName else {
            return server ?? Text("settings.interface.homeRows.otherRows")
        }
        guard let server else { return Text(verbatim: libraryName) }
        return Text(verbatim: "\(libraryName) · ") + server
    }
}
