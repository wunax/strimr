import SwiftUI

@MainActor
struct HomeRowsSettingsView: View {
    @State private var viewModel: HomeViewModel

    init(services: MediaServices, settingsManager: SettingsManager, libraryStore: LibraryStore) {
        _viewModel = State(
            initialValue: HomeViewModel(
                services: services,
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            ),
        )
    }

    var body: some View {
        List {
            Section {
                Text("settings.interface.homeRows.description")
                    .foregroundStyle(.secondary)
            }

            Section("settings.interface.homeRows.section") {
                if viewModel.isLoading, viewModel.availableRows.isEmpty {
                    ProgressView("home.loading")
                        .frame(maxWidth: .infinity)
                } else if let errorMessage = viewModel.errorMessage, viewModel.availableRows.isEmpty {
                    Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                        .foregroundStyle(.red)
                } else if viewModel.orderedRowsForEditing.isEmpty {
                    Text("common.empty.nothingToShow")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(Array(viewModel.orderedRowsForEditing.enumerated()), id: \.element.id) { index, row in
                        rowControls(at: index, row: row)
                    }
                }
            }

            Section {
                Button("settings.interface.homeRows.restoreDefaults", role: .destructive) {
                    viewModel.resetRowPreferences()
                }
            }
        }
        .listStyle(listStyle)
        .navigationTitle("settings.interface.homeRows.title")
        .task {
            await viewModel.load()
        }
        .refreshable {
            await viewModel.reload()
        }
    }

    @ViewBuilder
    private func rowControls(at index: Int, row: HomeRow) -> some View {
        #if os(tvOS)
            let isVisible = viewModel.isRowVisible(row.id)

            VStack(alignment: .leading, spacing: 12) {
                Text(row.title)
                    .font(.headline)

                HStack(spacing: 12) {
                    Button {
                        viewModel.setRowVisible(row.id, visible: !isVisible)
                    } label: {
                        tvOSActionLabel(
                            isVisible
                                ? "settings.interface.homeRows.hide"
                                : "settings.interface.homeRows.show",
                            systemImage: isVisible ? "eye.slash" : "eye",
                        )
                    }
                    .buttonStyle(.bordered)

                    Button {
                        viewModel.moveRow(at: index, by: -1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveUp", systemImage: "arrow.up")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                    .disabled(index == 0)

                    Button {
                        viewModel.moveRow(at: index, by: 1)
                    } label: {
                        tvOSActionLabel("settings.interface.homeRows.moveDown", systemImage: "arrow.down")
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.secondary)
                    .disabled(index == viewModel.orderedRowsForEditing.count - 1)
                }
            }
            .padding(.vertical, 8)
        #else
            HStack(spacing: 12) {
                Toggle(row.title, isOn: Binding(
                    get: { viewModel.isRowVisible(row.id) },
                    set: { viewModel.setRowVisible(row.id, visible: $0) },
                ))

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
                .disabled(index == viewModel.orderedRowsForEditing.count - 1)
            }
        #endif
    }

    private func tvOSActionLabel(_ title: LocalizedStringKey, systemImage: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: systemImage)
            Text(title)
        }
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
