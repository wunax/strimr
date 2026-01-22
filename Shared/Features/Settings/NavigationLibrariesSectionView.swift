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
            ForEach(viewModel.libraries) { library in
                Toggle(library.title, isOn: viewModel.navigationBinding(for: library))
                    .moveDisabled(!viewModel.isSelected(library))
            }
            .onMove(perform: viewModel.moveLibraries)
        }
    }
}
