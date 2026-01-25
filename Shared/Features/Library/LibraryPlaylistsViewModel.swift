import Foundation
import Observation

@MainActor
@Observable
final class LibraryPlaylistsViewModel {
    let library: Library
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    private var reachedEnd = false

    @ObservationIgnored private let context: PlexAPIContext

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard items.isEmpty else { return }
        await fetch(reset: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false)
    }

    private func fetch(reset: Bool) async {
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let playlistRepository = try? PlaylistRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
            return
        }

        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let start = reset ? 0 : items.count
            let response = try await playlistRepository.getPlaylists(
                sectionId: sectionId,
                pagination: PlexPagination(start: start, size: 20),
            )

            let newItems = (response.mediaContainer.metadata ?? [])
                .compactMap(MediaDisplayItem.init)
            let total = response.mediaContainer.totalSize ?? (start + newItems.count)

            if reset {
                items = newItems
            } else {
                items.append(contentsOf: newItems)
            }

            reachedEnd = items.count >= total || newItems.isEmpty
        } catch {
            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }
}
