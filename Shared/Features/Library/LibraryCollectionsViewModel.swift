import Foundation
import Observation

@MainActor
@Observable
final class LibraryCollectionsViewModel {
    let library: Library
    var items: [MediaDisplayItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    private var reachedEnd = false

    @ObservationIgnored private let context: PlexAPIContext
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        await fetch(reset: true, preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading || isLoadingMore) else { return }
        await fetch(reset: true, preservingExistingContent: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false, preservingExistingContent: false)
    }

    private func fetch(reset: Bool, preservingExistingContent: Bool) async {
        guard let sectionId = library.sectionId else {
            handleLoadError(
                String(localized: "errors.missingLibraryIdentifier"),
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            handleLoadError(
                String(localized: "errors.selectServer.browseLibrary"),
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
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
            let response = try await sectionRepository.getSectionCollections(
                sectionId: sectionId,
                includeCollections: true,
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
            handleLoadError(
                error.localizedDescription,
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
        }
    }

    private func resetState(error: String? = nil) {
        items = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }

    private func handleLoadError(_ message: String, reset: Bool, preservingExistingContent: Bool) {
        if preservingExistingContent, !items.isEmpty {
            errorMessage = nil
            isLoading = false
            isLoadingMore = false
        } else if reset {
            resetState(error: message)
        } else {
            errorMessage = message
            isLoadingMore = false
        }
    }
}
