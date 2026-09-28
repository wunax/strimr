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
        if viewModel.isLoading {
            ProgressView()
        } else if viewModel.libraries.isEmpty {
            Text("settings.interface.displayedLibraries.empty")
                .foregroundStyle(.secondary)
        } else {
            #if os(tvOS)
                ForEach(Array(viewModel.libraries.enumerated()), id: \.element.id) { index, library in
                    VStack(alignment: .leading, spacing: 16) {
                        Toggle(library.title, isOn: viewModel.navigationBinding(for: library))
                            .settingsFocus("navigation-library-\(library.id)")

                        if viewModel.isSelected(library) {
                            HStack(spacing: 16) {
                                Button {
                                    viewModel.moveLibraries(from: IndexSet(integer: index), to: index - 1)
                                } label: {
                                    Image(systemName: "arrow.up")
                                }
                                .accessibilityLabel(Text("settings.interface.homeRows.moveUp"))
                                .settingsFocus("navigation-library-\(library.id)-up")
                                .disabled(index == 0)

                                Button {
                                    viewModel.moveLibraries(from: IndexSet(integer: index), to: index + 2)
                                } label: {
                                    Image(systemName: "arrow.down")
                                }
                                .accessibilityLabel(Text("settings.interface.homeRows.moveDown"))
                                .settingsFocus("navigation-library-\(library.id)-down", exitsLeft: false)
                                .disabled(index == viewModel.libraries.filter { viewModel.isSelected($0) }.count - 1)
                            }
                        }
                    }
                }
            #else
                ForEach(viewModel.libraries) { library in
                    Toggle(library.title, isOn: viewModel.navigationBinding(for: library))
                        .id("navigation-library-\(library.id)")
                        .moveDisabled(!viewModel.isSelected(library))
                }
                .onMove(perform: viewModel.moveLibraries)
            #endif
        }
    }
}
