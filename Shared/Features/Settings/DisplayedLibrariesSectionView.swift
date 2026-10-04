import SwiftUI

@MainActor
struct DisplayedLibrariesSectionView: View {
    @State private var viewModel: DisplayedLibrariesViewModel

    init(settingsManager: SettingsManager, libraryStore: LibraryStore) {
        _viewModel = State(
            initialValue: DisplayedLibrariesViewModel(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            ),
        )
    }

    var body: some View {
        Section {
            rows
        } header: {
            Text("settings.interface.displayedLibraries")
        }
        .task {
            await viewModel.loadLibraries()
        }
    }

    @ViewBuilder
    private var rows: some View {
        if viewModel.isLoading, viewModel.libraries.isEmpty {
            ProgressView()
        } else if viewModel.libraries.isEmpty {
            Text("settings.interface.displayedLibraries.empty")
                .foregroundStyle(.secondary)
        } else {
            #if os(tvOS)
                ForEach(Array(viewModel.libraries.enumerated()), id: \.element.identity) { index, library in
                    let key = "displayed-library-\(library.identity.stableKey)"
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: viewModel.displayedBinding(for: library)) {
                            LibrarySettingsLabel(title: library.title, subtitle: viewModel.subtitle(for: library))
                        }
                        .settingsFocus(key)

                        HStack(spacing: 16) {
                            Button {
                                viewModel.moveLibraries(from: IndexSet(integer: index), to: index - 1)
                            } label: {
                                Image(systemName: "arrow.up")
                            }
                            .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                            .settingsFocus("\(key)-up")
                            .disabled(index == 0)

                            Button {
                                viewModel.moveLibraries(from: IndexSet(integer: index), to: index + 2)
                            } label: {
                                Image(systemName: "arrow.down")
                            }
                            .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                            .settingsFocus("\(key)-down", exitsLeft: false)
                            .disabled(index == viewModel.libraries.count - 1)
                        }
                    }
                }
            #else
                ForEach(viewModel.libraries, id: \.identity) { library in
                    Toggle(isOn: viewModel.displayedBinding(for: library)) {
                        LibrarySettingsLabel(title: library.title, subtitle: viewModel.subtitle(for: library))
                    }
                    .id("displayed-library-\(library.identity.stableKey)")
                }
                .onMove(perform: viewModel.moveLibraries)
            #endif
        }
    }
}

/// Library name with its server underneath when the profile has several servers.
struct LibrarySettingsLabel: View {
    let title: String
    let subtitle: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title)
            if let subtitle {
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}
