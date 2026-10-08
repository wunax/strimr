import Observation
import SwiftUI

/// Hiding and ordering of the profile's libraries, all servers in one list.
@MainActor
@Observable
final class DisplayedLibrariesViewModel {
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore

    var libraries: [Library] {
        libraryStore.libraries
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
        try? await libraryStore.loadLibraries()
    }

    func subtitle(for library: Library) -> String? {
        libraryStore.showsServerNames ? libraryStore.serverName(for: library) : nil
    }

    func displayedBinding(for library: Library) -> Binding<Bool> {
        Binding(
            get: {
                !self.settingsManager.libraryPreferences(profileID: self.libraryStore.profileID)
                    .isHidden(library.identity)
            },
            set: { displayed in
                self.settingsManager.updateLibraryPreferences(profileID: self.libraryStore.profileID) {
                    $0.setHidden(library.identity, hidden: !displayed)
                }
            },
        )
    }

    func moveLibrary(at index: Int, by offset: Int) {
        var ordered = libraries.map(\.identity)
        let destination = index + offset
        guard ordered.indices.contains(index), ordered.indices.contains(destination) else { return }
        ordered.insert(ordered.remove(at: index), at: destination)
        settingsManager.updateLibraryPreferences(profileID: libraryStore.profileID) {
            $0.setOrder(ordered)
        }
    }
}
