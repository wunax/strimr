import Foundation
import Observation

/// The unified library list of the active profile.
@MainActor
@Observable
final class LibraryViewModel {
    var errorMessage: String?
    var artworkResources: [LibraryIdentity: ArtworkResource] = [:]

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

    func artwork(for library: Library) -> ArtworkResource? {
        artworkResources[library.identity]
    }

    func ensureArtwork(for library: Library) async {
        guard artworkResources[library.identity] == nil,
              let services = sessionManager.registry.services(for: library.server)
        else { return }
        do {
            if let resource = try await services.library.randomArtwork(for: library) {
                artworkResources[library.identity] = resource
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation, !error.isTransportFailure else { return }
            ErrorReporter.capture(error)
        }
    }
}
