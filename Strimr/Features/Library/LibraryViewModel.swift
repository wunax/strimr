import Foundation
import Observation

@MainActor
@Observable
final class LibraryViewModel {
    var libraries: [Library] = []
    var isLoading = false
    var errorMessage: String?
    var artworkURLs: [String: URL] = [:]

    @ObservationIgnored private let plexApiManager: PlexAPIManager

    init(plexApiManager: PlexAPIManager) {
        self.plexApiManager = plexApiManager
    }

    func load() async {
        guard let api = plexApiManager.server else {
            resetState(error: "Select a server to load libraries.")
            return
        }

        guard libraries.isEmpty else { return }
        await fetchLibraries(using: api)
    }

    private func fetchLibraries(using api: PlexMediaServerAPI) async {
        isLoading = true
        errorMessage = nil
        defer { isLoading = false }

        do {
            let response = try await api.getSections()
            let sections = response.mediaContainer.directory ?? []
            libraries = sections.map(Library.init)
        } catch {
            resetState(error: error.localizedDescription)
        }
    }

    func artworkURL(for library: Library) -> URL? {
        artworkURLs[library.id]
    }

    func ensureArtwork(for library: Library) async {
        guard artworkURLs[library.id] == nil else { return }
        guard let sectionId = library.sectionId else { return }
        guard let api = plexApiManager.server else { return }
        do {
            let itemContainer = try await api.getSectionsItems(
                sectionId: sectionId,
                params: PlexSectionItemsParams(sort: "random", limit: 1),
                pagination: PlexPagination(start: 0, size: 1)
            )

            if let item = itemContainer.mediaContainer.metadata?.first {
                let path = item.art ?? item.thumb
                if let url = path.flatMap({ api.transcodeImageURL(path: $0, width: 800, height: 450) }) {
                    await MainActor.run {
                        self.artworkURLs[library.id] = url
                    }
                }
            }
        } catch {
            await MainActor.run {
                self.artworkURLs[library.id] = nil
            }
        }
    }

    private func resetState(error: String? = nil) {
        libraries = []
        errorMessage = error
        isLoading = false
        artworkURLs = [:]
    }
}
