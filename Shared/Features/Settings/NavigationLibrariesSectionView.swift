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
            ForEach(Array(viewModel.libraries.enumerated()), id: \.element.identity) { index, library in
                LibraryOrderRow(
                    title: library.title,
                    subtitle: viewModel.subtitle(for: library),
                    isOn: viewModel.navigationBinding(for: library),
                    key: "navigation-library-\(library.identity.stableKey)",
                    canReorder: viewModel.isSelected(library),
                    canMoveUp: index > 0,
                    canMoveDown: index < viewModel.selectedCount - 1,
                ) { offset in
                    viewModel.moveLibrary(at: index, by: offset)
                }
            }
        }
    }
}
