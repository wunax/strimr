import Observation
import SwiftUI

@MainActor
@Observable
final class NavigationLibrariesViewModel {
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore
    private var navigationLibraryIds: [String]

    var libraries: [Library] {
        let allLibraries = libraryStore.libraries
        let selectedIds = navigationLibraryIds
        let libraryById = Dictionary(uniqueKeysWithValues: allLibraries.map { ($0.id, $0) })

        let selectedLibraries = selectedIds.compactMap { libraryById[$0] }
        let selectedSet = Set(selectedIds)
        let unselectedLibraries = allLibraries
            .filter { !selectedSet.contains($0.id) }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }

        return selectedLibraries + unselectedLibraries
    }

    var isLoading: Bool {
        libraryStore.isLoading
    }

    var loadFailed: Bool {
        libraryStore.loadFailed
    }

    init(settingsManager: SettingsManager, libraryStore: LibraryStore) {
        self.settingsManager = settingsManager
        self.libraryStore = libraryStore
        navigationLibraryIds = settingsManager.interface.navigationLibraryIds
    }

    func loadLibraries() async {
        guard !libraryStore.isLoading else { return }
        guard libraryStore.libraries.isEmpty else {
            pruneNavigationLibraries(with: libraryStore.libraries)
            return
        }

        do {
            try await libraryStore.loadLibraries()
            pruneNavigationLibraries(with: libraryStore.libraries)
        } catch {}
    }

    func navigationBinding(for library: Library) -> Binding<Bool> {
        Binding(
            get: { self.navigationLibraryIds.contains(library.id) },
            set: { self.setLibraryNavigationEnabled(library.id, enabled: $0) }
        )
    }

    func isSelected(_ library: Library) -> Bool {
        navigationLibraryIds.contains(library.id)
    }

    func moveLibraries(from source: IndexSet, to destination: Int) {
        var orderedLibraries = libraries
        orderedLibraries.move(fromOffsets: source, toOffset: destination)
        let updatedIds = orderedLibraries
            .filter { isSelected($0) }
            .map(\.id)
        updateNavigationLibraryIds(updatedIds)
    }

    private func setLibraryNavigationEnabled(_ libraryId: String, enabled: Bool) {
        var storedIds = navigationLibraryIds
        if enabled {
            if !storedIds.contains(libraryId) {
                storedIds.append(libraryId)
            }
        } else {
            storedIds.removeAll { $0 == libraryId }
        }
        updateNavigationLibraryIds(storedIds)
    }

    private func pruneNavigationLibraries(with libraries: [Library]) {
        let availableIds = Set(libraries.map(\.id))
        let storedIds = navigationLibraryIds
        let prunedIds = storedIds.filter { availableIds.contains($0) }
        if prunedIds.count != storedIds.count {
            updateNavigationLibraryIds(prunedIds)
        }
    }

    private func updateNavigationLibraryIds(_ ids: [String]) {
        navigationLibraryIds = ids
        settingsManager.setNavigationLibraryIds(ids)
    }
}
