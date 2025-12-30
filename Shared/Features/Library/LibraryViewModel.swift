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
    var artworkURLs: [String: URL] = [:]

    @ObservationIgnored private let context: PlexAPIContext
    private let libraryStore: LibraryStore

    init(context: PlexAPIContext, libraryStore: LibraryStore) {
        self.context = context
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
            if case PlexAPIError.missingConnection = error {
                errorMessage = String(localized: "errors.selectServer.loadLibraries")
            } else if case PlexAPIError.missingAuthToken = error {
                errorMessage = String(localized: "errors.selectServer.loadLibraries")
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    func artworkURL(for library: Library) -> URL? {
        artworkURLs[library.id]
    }

    func ensureArtwork(for library: Library) async {
        guard artworkURLs[library.id] == nil else { return }
        guard let sectionId = library.sectionId else { return }
        guard
            let sectionRepository = try? SectionRepository(context: context),
            let imageRepository = try? ImageRepository(context: context)
        else { return }
        do {
            let itemContainer = try await sectionRepository.getSectionsItems(
                sectionId: sectionId,
                params: SectionRepository.SectionItemsParams(sort: "random", limit: 1),
                pagination: PlexPagination(start: 0, size: 1)
            )

            if let item = itemContainer.mediaContainer.metadata?.first {
                let path = item.art ?? item.thumb
                if let url = path.flatMap({ imageRepository.transcodeImageURL(path: $0, width: 800, height: 450) }) {
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
}
