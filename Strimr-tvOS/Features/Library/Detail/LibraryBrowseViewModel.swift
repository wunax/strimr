import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseViewModel {
    struct SectionCharacter: Identifiable, Hashable {
        let id: String
        let title: String
        let size: Int
        let startIndex: Int
    }

    let library: Library
    var itemsByIndex: [Int: MediaDisplayItem] = [:]
    var totalItemCount = 0
    var sectionCharacters: [SectionCharacter] = []
    var isLoading = false
    var errorMessage: String?
    private var loadedPageStarts: Set<Int> = []
    private var loadingPageStarts: Set<Int> = []

    @ObservationIgnored private let context: PlexAPIContext
    private let pageSize = 40

    init(library: Library, context: PlexAPIContext) {
        self.library = library
        self.context = context
    }

    func load() async {
        guard itemsByIndex.isEmpty else { return }
        isLoading = true
        defer { isLoading = false }
        await fetchCharactersIfNeeded()
        await loadPage(start: 0)
    }

    func loadPagesAround(index: Int) async {
        guard index >= 0 else { return }
        let pageStart = max(0, (index / pageSize) * pageSize)
        if itemsByIndex[index] == nil,
           loadedPageStarts.contains(pageStart),
           !loadingPageStarts.contains(pageStart)
        {
            loadedPageStarts.remove(pageStart)
        }
        let pageStarts = [
            pageStart - (pageSize * 2),
            pageStart - pageSize,
            pageStart,
            pageStart + pageSize,
            pageStart + (pageSize * 2),
        ]
        for start in pageStarts where start >= 0 && (totalItemCount == 0 || start < totalItemCount) {
            await loadPage(start: start)
        }
    }

    private func fetchCharactersIfNeeded() async {
        guard sectionCharacters.isEmpty else { return }
        guard let sectionId = library.sectionId else { return }
        guard let sectionRepository = try? SectionRepository(context: context) else { return }

        do {
            let response = try await sectionRepository.getSectionFirstCharacters(sectionId: sectionId)
            let directories = response.mediaContainer.directory ?? []
            var runningIndex = 0
            var characters: [SectionCharacter] = []

            for directory in directories {
                let size = max(0, directory.size ?? 0)
                guard size > 0 else { continue }
                let title = directory.title ?? directory.key ?? "#"
                let identifier = "\(title)-\(runningIndex)"
                characters.append(
                    SectionCharacter(
                        id: identifier,
                        title: title,
                        size: size,
                        startIndex: runningIndex,
                    ),
                )
                runningIndex += size
            }

            sectionCharacters = characters
            totalItemCount = max(totalItemCount, runningIndex)
        } catch {
            if itemsByIndex.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPage(start: Int) async {
        guard !loadedPageStarts.contains(start), !loadingPageStarts.contains(start) else { return }
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard let sectionRepository = try? SectionRepository(context: context) else {
            resetState(error: String(localized: "errors.selectServer.browseLibrary"))
            return
        }

        errorMessage = nil
        loadingPageStarts.insert(start)
        defer {
            loadingPageStarts.remove(start)
        }

        do {
            let response = try await sectionRepository.getSectionsItems(
                sectionId: sectionId,
                pagination: PlexPagination(start: start, size: pageSize),
            )

            let newItems = (response.mediaContainer.metadata ?? [])
                .compactMap(MediaDisplayItem.init)
            let total = response.mediaContainer.totalSize ?? (start + newItems.count)

            for (offset, item) in newItems.enumerated() {
                itemsByIndex[start + offset] = item
            }
            loadedPageStarts.insert(start)
            totalItemCount = max(totalItemCount, total)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resetState(error: String? = nil) {
        itemsByIndex = [:]
        totalItemCount = 0
        sectionCharacters = []
        errorMessage = error
        isLoading = false
        loadedPageStarts = []
        loadingPageStarts = []
    }
}
