import Observation
import SwiftUI

/// Libraries pinned in the tab bar or the sidebar, per profile.
@MainActor
@Observable
final class NavigationLibrariesViewModel {
    private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore

    private var navigationLibraries: [LibraryIdentity] {
        settingsManager.libraryPreferences(profileID: libraryStore.profileID).navigationLibraries
    }

    var libraries: [Library] {
        let allLibraries = libraryStore.libraries
        let selected = navigationLibraries
        let byIdentity = Dictionary(allLibraries.map { ($0.identity, $0) }, uniquingKeysWith: { first, _ in first })
        let selectedSet = Set(selected)
        return selected.compactMap { byIdentity[$0] } + allLibraries.filter { !selectedSet.contains($0.identity) }
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

    func navigationBinding(for library: Library) -> Binding<Bool> {
        Binding(
            get: { self.isSelected(library) },
            set: { self.setNavigationEnabled(library.identity, enabled: $0) },
        )
    }

    func isSelected(_ library: Library) -> Bool {
        navigationLibraries.contains(library.identity)
    }

    var selectedCount: Int {
        libraries.count(where: isSelected)
    }

    /// Reorders the pinned libraries; pinned libraries of servers missing from the list keep their place at the end.
    func moveLibraries(from source: IndexSet, to destination: Int) {
        var ordered = libraries
        ordered.move(fromOffsets: source, toOffset: destination)
        let visible = ordered.filter(isSelected).map(\.identity)
        let absent = navigationLibraries.filter { !visible.contains($0) }
        update(visible + absent)
    }

    private func setNavigationEnabled(_ library: LibraryIdentity, enabled: Bool) {
        var stored = navigationLibraries
        stored.removeAll { $0 == library }
        if enabled {
            stored.append(library)
        }
        update(stored)
    }

    private func update(_ libraries: [LibraryIdentity]) {
        settingsManager.updateLibraryPreferences(profileID: libraryStore.profileID) {
            $0.navigationLibraries = libraries
        }
    }
}
