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

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private var refreshGate = AutomaticRefreshGate()
    @ObservationIgnored private var commonItems: [MediaDisplayItem]?
    private let pageSize = 40

    init(
        library: Library,
        services: MediaServices,
        settingsManager _: SettingsManager,
    ) {
        self.library = library
        advancedService = services.library as? any PlexAdvancedLibraryService
        service = services.library
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
        guard let advancedService else { return }
        guard forceReload || sectionCharacters.isEmpty else { return }
        guard let sectionId = library.sectionId else { return }
        do {
            let values = try await advancedService.collectionCharacters(sectionID: sectionId)
            var runningIndex = 0
            var characters: [SectionCharacter] = []

            for value in values {
                let size = value.size
                let title = value.title
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
        guard let advancedService else {
            await loadCommonPage(
                start: start,
                reset: reset,
                preservingExistingContent: preservingExistingContent
            )
            return
        }
        guard let sectionId = library.sectionId else {
            handleLoadError(
                String(localized: "errors.missingLibraryIdentifier"),
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
            let response = try await advancedService.collectionPage(
                sectionID: sectionId,
                startIndex: start,
                limit: pageSize
            )

            let newItems = response.items
            let total = response.totalCount ?? (start + newItems.count)

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

    private func loadCommonPage(
        start: Int,
        reset: Bool,
        preservingExistingContent: Bool
    ) async {
        if reset {
            commonItems = nil
            loadedPageStarts.removeAll()
        }
        errorMessage = nil
        loadingPageStarts.insert(start)
        defer { loadingPageStarts.remove(start) }

        do {
            let allItems: [MediaDisplayItem]
            if let commonItems {
                allItems = commonItems
            } else {
                allItems = try await service.collections(in: library).map(MediaDisplayItem.collection)
                commonItems = allItems
            }
            let page = Array(allItems.dropFirst(start).prefix(pageSize))
            if reset { itemsByIndex = [:] }
            for (offset, item) in page.enumerated() {
                itemsByIndex[start + offset] = item
            }
            loadedPageStarts.insert(start)
            totalItemCount = allItems.count
        } catch {
            if !error.isCancellation {
                ErrorReporter.capture(error)
                handleLoadError(
                    error.localizedDescription,
                    reset: reset,
                    preservingExistingContent: preservingExistingContent
                )
            }
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
        commonItems = nil
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
