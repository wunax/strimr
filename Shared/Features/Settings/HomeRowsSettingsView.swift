import SwiftUI

@MainActor
struct HomeRowsSettingsView: View {
    @State private var viewModel: HomeViewModel

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
                .listStyle(listStyle)
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
        Section("settings.interface.homeRows.section") {
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
        }

        ForEach(viewModel.availableRowGroups) { group in
            Section {
                ForEach(group.rows) { row in
                    availableRowControls(row)
                }
            } header: {
                groupHeader(group)
            } footer: {
                if group.isExcludedFromServerHome {
                    Text("settings.homeRows.excludedFromServerHome")
                }
            }
        }

        Section {
            Button("settings.interface.homeRows.restoreDefaults", role: .destructive) {
                viewModel.resetRowPreferences()
            }
            #if os(tvOS)
            .settingsFocus("restoreRows", isDefault: shownRows.isEmpty)
            #endif
        }
    }

    @ViewBuilder
    private func shownRowControls(at index: Int, row: HomeRow, count: Int) -> some View {
        #if os(tvOS)
            VStack(alignment: .leading, spacing: 12) {
                Text(row.title)
                    .font(.headline)
                rowSubtitle(for: row)

                HStack(spacing: 12) {
                    Button {
                        viewModel.setRowVisible(row.id, visible: false)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.hide", systemImage: "eye")
                    }
                    .buttonStyle(.bordered)
                    .settingsFocus("row-\(row.id)-visibility", isDefault: index == 0)

                    Button {
                        viewModel.moveRow(at: index, by: -1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveUp", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                    .settingsFocus("row-\(row.id)-up", exitsLeft: false)
                    .disabled(index == 0)

                    Button {
                        viewModel.moveRow(at: index, by: 1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveDown", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                    .settingsFocus("row-\(row.id)-down", exitsLeft: false)
                    .disabled(index == count - 1)
                }
            }
            .padding(.vertical, 8)
        #else
            HStack(spacing: 12) {
                Toggle(isOn: Binding(
                    get: { true },
                    set: { viewModel.setRowVisible(row.id, visible: $0) },
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(row.title)
                        rowSubtitle(for: row)
                    }
                }

                Button {
                    viewModel.moveRow(at: index, by: -1)
                } label: {
                    Image(systemName: "arrow.up")
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                .disabled(index == 0)

                Button {
                    viewModel.moveRow(at: index, by: 1)
                } label: {
                    Image(systemName: "arrow.down")
                }
                .foregroundStyle(.secondary)
                .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                .disabled(index == count - 1)
            }
        #endif
    }

    @ViewBuilder
    private func availableRowControls(_ row: HomeRow) -> some View {
        #if os(tvOS)
            Button {
                viewModel.setRowVisible(row.id, visible: true)
            } label: {
                HStack(spacing: 12) {
                    Image(systemName: "plus")
                    Text(row.title)
                }
            }
            .settingsFocus("row-\(row.id)-visibility")
        #else
            Toggle(row.title, isOn: Binding(
                get: { false },
                set: { viewModel.setRowVisible(row.id, visible: $0) },
            ))
        #endif
    }

    private func groupHeader(_ group: HomeRowGroup) -> Text {
        let server = group.serverName.map { Text("settings.homeRows.serverSubtitle \($0)") }
        guard let libraryName = group.libraryName else {
            return server ?? Text("settings.interface.homeRows.otherRows")
        }
        guard let server else { return Text(verbatim: libraryName) }
        return Text(verbatim: "\(libraryName) · ") + server
    }

    /// Tells apart rows sharing a title in different libraries or servers.
    @ViewBuilder
    private func rowSubtitle(for row: HomeRow) -> some View {
        if let subtitle = subtitle(for: row) {
            subtitle
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func subtitle(for row: HomeRow) -> Text? {
        let server = row.serverName.map { Text("settings.homeRows.serverSubtitle \($0)") }
        guard let libraryName = row.libraryName else { return server }
        guard let server else { return Text(verbatim: libraryName) }
        return Text(verbatim: "\(libraryName) · ") + server
    }

    private func tvOSActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
        }
        .accessibilityLabel(Text(title))
    }

    private var listStyle: some ListStyle {
        #if os(macOS)
            .inset
        #elseif os(tvOS)
            .plain
        #else
            .insetGrouped
        #endif
    }
}
