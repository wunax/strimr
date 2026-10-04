import SwiftUI

@MainActor
struct NavigationLibrariesSectionView: View {
    @State private var viewModel: NavigationLibrariesViewModel

    init(settingsManager: SettingsManager, libraryStore: LibraryStore) {
        _viewModel = State(
            initialValue: NavigationLibrariesViewModel(
                settingsManager: settingsManager,
                libraryStore: libraryStore,
            ),
        )
    }

    var body: some View {
        Section {
            rows
        } header: {
            Text("settings.interface.navigationLibraries")
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
                    let key = "navigation-library-\(library.identity.stableKey)"
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(isOn: viewModel.navigationBinding(for: library)) {
                            LibrarySettingsLabel(title: library.title, subtitle: viewModel.subtitle(for: library))
                        }
                        .settingsFocus(key)

                        if viewModel.isSelected(library) {
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
                                .disabled(index == viewModel.selectedCount - 1)
                            }
                        }
                    }
                }
            #else
                ForEach(viewModel.libraries, id: \.identity) { library in
                    Toggle(isOn: viewModel.navigationBinding(for: library)) {
                        LibrarySettingsLabel(title: library.title, subtitle: viewModel.subtitle(for: library))
                    }
                    .id("navigation-library-\(library.identity.stableKey)")
                    .moveDisabled(!viewModel.isSelected(library))
                }
                .onMove(perform: viewModel.moveLibraries)
            #endif
        }
    }
}
