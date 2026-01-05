import Observation
import SwiftUI

@MainActor
@Observable
final class DisplayedLibrariesViewModel {
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore

    var libraries: [Library] {
        libraryStore.libraries
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
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
    }

    func loadLibraries() async {
        guard !libraryStore.isLoading else { return }
        guard libraryStore.libraries.isEmpty else { return }

        do {
            try await libraryStore.loadLibraries()
            pruneHiddenLibraries(with: libraries)
        } catch {}
    }

    func displayedBinding(for library: Library) -> Binding<Bool> {
        Binding(
            get: { !self.settingsManager.interface.hiddenLibraryIds.contains(library.id) },
            set: { self.settingsManager.setLibraryDisplayed(library.id, displayed: $0) }
        )
    }

    private func pruneHiddenLibraries(with libraries: [Library]) {
        let availableIds = Set(libraries.map(\.id))
        let storedHiddenIds = settingsManager.interface.hiddenLibraryIds
        let prunedHiddenIds = storedHiddenIds.filter { availableIds.contains($0) }
        if prunedHiddenIds.count != storedHiddenIds.count {
            settingsManager.setHiddenLibraryIds(prunedHiddenIds)
        }
    }
}
