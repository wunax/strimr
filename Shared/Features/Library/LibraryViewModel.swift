import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var libraries: [Library] {
        libraryStore.libraries
    }

    var isLoading: Bool {
        libraryStore.isLoading
    }

    var errorMessage: String?
    var artworkResources: [String: ArtworkResource] = [:]

    @ObservationIgnored private let service: any MediaLibraryService
    private let libraryStore: LibraryStore

    init(services: MediaServices, libraryStore: LibraryStore) {
        service = services.library
        self.libraryStore = libraryStore
    }

    func load() async {
        guard libraries.isEmpty else { return }
        await fetchLibraries()
    }

    private func fetchLibraries() async {
        errorMessage = nil

        do {
            try await libraryStore.loadLibraries()
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if case PlexAPIError.missingConnection = error {
                errorMessage = String(localized: "errors.selectServer.loadLibraries")
            } else if case PlexAPIError.missingAuthToken = error {
                errorMessage = String(localized: "errors.selectServer.loadLibraries")
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func artwork(for library: Library) -> ArtworkResource? {
        artworkResources[library.id]
    }

    func ensureArtwork(for library: Library) async {
        guard artworkResources[library.id] == nil else { return }
        do {
            if let resource = try await service.randomArtwork(for: library) {
                artworkResources[library.id] = resource
            }
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            ErrorReporter.capture(error)
            await MainActor.run {
                self.artworkResources[library.id] = nil
            }
        }
    }
}
