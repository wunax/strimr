import Foundation
import Observation

/// The unified library list of the active profile.
@MainActor
@Observable
final class LibraryViewModel {
    var errorMessage: String?
    var previews: [LibraryIdentity: LibraryPreview] = [:]

    @ObservationIgnored private let sessionManager: SessionManager
    @ObservationIgnored private let settingsManager: SettingsManager
    private let libraryStore: LibraryStore

    init(sessionManager: SessionManager, libraryStore: LibraryStore, settingsManager: SettingsManager) {
        self.sessionManager = sessionManager
        self.libraryStore = libraryStore
        self.settingsManager = settingsManager
    }

    private var profileID: String {
        sessionManager.activeProfile?.id ?? ""
    }

    var libraries: [Library] {
        libraryStore.libraries.filter(isDisplayed)
    }

    var visibleLibraries: [Library] {
        let preferences = settingsManager.libraryPreferences(profileID: profileID)
        return libraries.filter { !preferences.isHidden($0.identity) }
    }

    var hiddenLibraries: [Library] {
        let preferences = settingsManager.libraryPreferences(profileID: profileID)
        return libraries.filter { preferences.isHidden($0.identity) }
    }

    var isLoading: Bool {
        libraryStore.isLoading
    }

    func isHidden(_ library: Library) -> Bool {
        settingsManager.libraryPreferences(profileID: profileID).isHidden(library.identity)
    }

    func isPinned(_ library: Library) -> Bool {
        settingsManager.libraryPreferences(profileID: profileID).isPinned(library.identity)
    }

    func setHidden(_ library: Library, hidden: Bool) {
        settingsManager.updateLibraryPreferences(profileID: profileID) {
            $0.setHidden(library.identity, hidden: hidden)
        }
    }

    func setPinned(_ library: Library, pinned: Bool) {
        settingsManager.updateLibraryPreferences(profileID: profileID) {
            $0.setPinned(library.identity, pinned: pinned)
        }
    }

    /// The server name is only shown when the list covers several servers.
    func subtitle(for library: Library) -> String? {
        guard libraryStore.showsServerNames else { return nil }
        return libraryStore.serverName(for: library)
    }

    /// Jellyfin exposes collections and playlists as libraries; they follow the display settings.
    private func isDisplayed(_ library: Library) -> Bool {
        guard library.server.provider == .jellyfin else { return true }
        if library.type == .collection {
            return settingsManager.interface.displayCollections
        }
        if library.type == .playlist {
            return settingsManager.interface.displayPlaylists
        }
        return true
    }

    func load() async {
        errorMessage = nil
        do {
            try await libraryStore.loadLibraries()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func syncServers() async {
        await libraryStore.syncServers()
    }

    func artworks(for library: Library) -> [ArtworkResource] {
        previews[library.identity]?.artworks ?? []
    }

    /// Size of the library, then its server when the list covers several, e.g. "1245 movies · Living room".
    func caption(for library: Library) -> String? {
        let count = previews[library.identity]?.itemCount.map { count in
            switch library.type {
            case .movie: String(localized: "library.count.movies \(count)")
            case .series: String(localized: "library.count.shows \(count)")
            default: String(localized: "library.browse.count.items \(count)")
            }
        }
        let parts = [count, subtitle(for: library)].compactMap(\.self)
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    func ensurePreview(for library: Library) async {
        guard previews[library.identity] == nil,
              let services = sessionManager.registry.services(for: library.server)
        else { return }
        do {
            if let preview = try await services.library.preview(for: library) {
                previews[library.identity] = preview
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation, !error.isTransportFailure else { return }
            ErrorReporter.capture(error)
        }
    }
}
