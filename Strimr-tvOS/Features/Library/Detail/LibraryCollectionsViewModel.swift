import Foundation
import Observation

@MainActor
@Observable
final class LibraryCollectionsViewModel {
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
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()
    private let pageSize = 40

    init(
        library: Library,
        context: PlexAPIContext,
        settingsManager: SettingsManager,
    ) {
        self.library = library
        self.context = context
        self.settingsManager = settingsManager
    }

    func load() async {
        guard refreshGate.startInitialLoadIfNeeded() else { return }
        await reload()
    }

    func reload() async {
        resetState()
        isLoading = true
        defer { isLoading = false }
        await fetchCharactersIfNeeded(preservingExistingContent: false)
        await loadPage(start: 0, reset: true, preservingExistingContent: false)
    }

    func refreshIfNeeded(now: Date = Date()) async {
        guard refreshGate.shouldRefresh(now: now, isLoading: isLoading) else { return }

        isLoading = true
        defer { isLoading = false }
        await fetchCharactersIfNeeded(preservingExistingContent: true, forceReload: true)
        await loadPage(start: 0, reset: true, preservingExistingContent: true)
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

    private func fetchCharactersIfNeeded(
        preservingExistingContent: Bool,
        forceReload: Bool = false,
    ) async {
        guard forceReload || sectionCharacters.isEmpty else { return }
        guard let sectionId = library.sectionId else { return }
        guard let sectionRepository = try? SectionRepository(context: context) else { return }

        do {
            let response = try await sectionRepository.getSectionFirstCharacters(
                sectionId: sectionId,
                type: 18,
                includeCollections: true,
            )
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
            if preservingExistingContent, !itemsByIndex.isEmpty {
                errorMessage = nil
            } else if itemsByIndex.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPage(
        start: Int,
        reset: Bool = false,
        preservingExistingContent: Bool = false,
    ) async {
        guard reset || !loadedPageStarts.contains(start) else { return }
        guard !loadingPageStarts.contains(start) else { return }
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
            loadedPageStarts.remove(start)
        }
        errorMessage = nil
        loadingPageStarts.insert(start)
        defer {
            loadingPageStarts.remove(start)
        }

        do {
            let response = try await sectionRepository.getSectionCollections(
                sectionId: sectionId,
                includeCollections: true,
                pagination: PlexPagination(start: start, size: pageSize),
            )

            let newItems = (response.mediaContainer.metadata ?? [])
                .compactMap(MediaDisplayItem.init)
            let total = response.mediaContainer.totalSize ?? (start + newItems.count)

            if reset {
                itemsByIndex = [:]
                loadedPageStarts = []
            }
            for (offset, item) in newItems.enumerated() {
                itemsByIndex[start + offset] = item
            }
            loadedPageStarts.insert(start)
            totalItemCount = reset ? total : max(totalItemCount, total)
        } catch {
            handleLoadError(
                error.localizedDescription,
                reset: reset,
                preservingExistingContent: preservingExistingContent,
            )
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

    private func handleLoadError(_ message: String, reset: Bool, preservingExistingContent: Bool) {
        if preservingExistingContent, !itemsByIndex.isEmpty {
            errorMessage = nil
        } else if reset {
            resetState(error: message)
        } else {
            errorMessage = message
        }
    }
}
