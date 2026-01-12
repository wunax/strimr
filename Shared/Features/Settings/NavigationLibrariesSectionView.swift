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
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.interface.title")
                Text("settings.interface.navigationLibraries")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await viewModel.loadLibraries()
        }
    }
}
