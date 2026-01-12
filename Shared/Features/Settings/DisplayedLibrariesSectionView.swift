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
            if viewModel.isLoading {
                ProgressView()
            } else if viewModel.libraries.isEmpty {
                Text("settings.interface.displayedLibraries.empty")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(viewModel.libraries) { library in
                    Toggle(library.title, isOn: viewModel.displayedBinding(for: library))
                }
            }
        } header: {
            VStack(alignment: .leading, spacing: 4) {
                Text("settings.interface.title")
                Text("settings.interface.displayedLibraries")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
            }
        }
        .task {
            await viewModel.loadLibraries()
        }
    }
}
