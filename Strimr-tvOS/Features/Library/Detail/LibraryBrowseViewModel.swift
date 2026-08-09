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

    private struct FolderBreadcrumb: Identifiable, Equatable {
        let id: String
        let title: String
        let endpoint: PlexEndpoint
    }

    let library: Library
    var itemsByIndex: [Int: LibraryBrowseItem] = [:]
    var totalItemCount = 0
    var sectionCharacters: [SectionCharacter] = []
    var isLoading = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel

    private var loadedPageStarts: Set<Int> = []
    private var loadingPageStarts: Set<Int> = []
    private var folderStack: [FolderBreadcrumb] = []
    private var hasLoadedMeta = false

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private let settingsManager: SettingsManager
    private let pageSize = 40

    init(
        library: Library,
        services: MediaServices,
        settingsManager: SettingsManager,
    ) {
        self.library = library
        advancedService = services.library as? any PlexAdvancedLibraryService
        service = services.library
        self.settingsManager = settingsManager
        controls = LibraryBrowseControlsViewModel(advancedService: services.library as? any PlexAdvancedLibraryService)
        controls.onSelectionChanged = { [weak self] in
            Task { await self?.refresh() }
        }
        controls.onDisplayTypeChanged = { [weak self] in
            guard let self else { return }
            folderStack = []
            Task { await self.refresh() }
        }
    }

    var canNavigateBack: Bool {
        !folderStack.isEmpty
    }

    var showsCharacterColumn: Bool {
        supportsSectionCharacters && !sectionCharacters.isEmpty
    }

    func load() async {
        guard itemsByIndex.isEmpty else { return }
        await refresh()
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

    func enterFolder(_ folder: LibraryBrowseFolderItem) {
        guard let endpoint = PlexEndpoint(key: folder.key) else { return }
        folderStack.append(
            FolderBreadcrumb(
                id: folder.key,
                title: folder.title,
                endpoint: endpoint,
            ),
        )
        Task { await refresh() }
    }

    func navigateBack() {
        guard !folderStack.isEmpty else { return }
        folderStack.removeLast()
        Task { await refresh() }
    }

    func refresh() async {
        resetState()
        isLoading = true
        defer { isLoading = false }
        await loadPage(start: 0)
        await fetchCharactersIfNeeded()
    }

    private func fetchCharactersIfNeeded() async {
        guard let advancedService else { return }
        guard sectionCharacters.isEmpty else { return }
        guard supportsSectionCharacters else { return }
        guard let sectionId = library.sectionId else { return }
        do {
            let endpoint = resolvedEndpoint(sectionId: sectionId)
            guard let firstCharacterEndpoint = firstCharacterEndpoint(from: endpoint) else { return }
            let includeCollections = settingsManager.interface.displayCollections ? true : nil
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: false,
            )

            let values = try await advancedService.sectionCharacters(
                path: firstCharacterEndpoint.path,
                queryItems: queryItems
            )
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
            if itemsByIndex.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPage(start: Int) async {
        guard !loadedPageStarts.contains(start), !loadingPageStarts.contains(start) else { return }
        guard let advancedService else {
            await loadCommonPage(start: start)
            return
        }
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        errorMessage = nil
        loadingPageStarts.insert(start)
        defer {
            loadingPageStarts.remove(start)
        }

        do {
            let endpoint = resolvedEndpoint(sectionId: sectionId)
            let includeCollections = settingsManager.interface.displayCollections ? true : nil
            let includeMeta = !hasLoadedMeta
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: includeMeta,
            )

            let response = try await advancedService.advancedBrowse(
                path: endpoint.path,
                queryItems: queryItems,
                startIndex: start,
                limit: pageSize
            )

            if includeMeta, let meta = response.meta {
                controls.applyMeta(meta)
                hasLoadedMeta = true
            }

            let newItems = response.items
            let total = response.totalCount

            for (offset, item) in newItems.enumerated() {
                itemsByIndex[start + offset] = item
            }
            loadedPageStarts.insert(start)
            totalItemCount = max(totalItemCount, total)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func loadCommonPage(start: Int) async {
        errorMessage = nil
        loadingPageStarts.insert(start)
        defer { loadingPageStarts.remove(start) }

        do {
            let page = try await service.items(
                in: library,
                parentID: nil,
                startIndex: start,
                limit: pageSize
            )
            for (offset, item) in page.items.enumerated() {
                itemsByIndex[start + offset] = .media(item)
            }
            loadedPageStarts.insert(start)
            totalItemCount = page.totalCount ?? (start + page.items.count)
        } catch {
            if !error.isCancellation {
                ErrorReporter.capture(error)
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resolvedEndpoint(sectionId: Int) -> PlexEndpoint {
        if let currentFolderEndpoint {
            return currentFolderEndpoint
        }
        if let selectedDisplayType = controls.selectedDisplayType,
           let endpoint = PlexEndpoint(key: selectedDisplayType.key)
        {
            return endpoint
        }

        let path = "/library/sections/\(sectionId)/all"
        let typeValue = defaultTypeQueryValue
        let queryItems = [URLQueryItem.make("type", typeValue)].compactMap(\.self)
        return PlexEndpoint(path: path, queryItems: queryItems)
    }

    private var currentFolderEndpoint: PlexEndpoint? {
        folderStack.last?.endpoint
    }

    private var defaultTypeQueryValue: String? {
        switch library.type {
        case .movie:
            "1"
        case .series:
            "2"
        default:
            "1,2"
        }
    }

    private func firstCharacterEndpoint(from endpoint: PlexEndpoint) -> PlexEndpoint? {
        let components = endpoint.path.split(separator: "/")
        guard components.last == "all" else { return nil }
        let prefix = components.dropLast().joined(separator: "/")
        let path = "/\(prefix)/firstCharacter"
        return PlexEndpoint(path: path, queryItems: endpoint.queryItems)
    }

    private var supportsSectionCharacters: Bool {
        guard advancedService != nil else { return false }
        guard let sectionId = library.sectionId else { return false }
        let endpoint = resolvedEndpoint(sectionId: sectionId)
        return firstCharacterEndpoint(from: endpoint) != nil
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
