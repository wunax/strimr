import Observation
import SwiftUI

@MainActor
@Observable
final class DisplayedLibrariesViewModel {
    private let settingsManager: SettingsManager
    private let plexApiContext: PlexAPIContext

    var libraries: [Library] = []
    var isLoading = false
    var loadFailed = false

    init(settingsManager: SettingsManager, plexApiContext: PlexAPIContext) {
        self.settingsManager = settingsManager
        self.plexApiContext = plexApiContext
    }

    func loadLibraries() async {
        guard !isLoading else { return }
        guard libraries.isEmpty else { return }

        isLoading = true
        loadFailed = false
        defer { isLoading = false }

        do {
            let repository = try SectionRepository(context: plexApiContext)
            let response = try await repository.getSections()
            let sections = response.mediaContainer.directory ?? []
            let resolvedLibraries = sections
                .map(Library.init)
                .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
            libraries = resolvedLibraries
            pruneHiddenLibraries(with: resolvedLibraries)
        } catch {
            loadFailed = true
        }
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
