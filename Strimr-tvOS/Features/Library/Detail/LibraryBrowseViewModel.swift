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
    var scrollResetID = 0
    private(set) var layout: LibraryBrowseLayout
    private(set) var showsFolderTree: Bool
    private(set) var folderTree: FolderTreeModel?

    private var loadedPageStarts: Set<Int> = []
    private var loadingPageStarts: Set<Int> = []
    private var folderStack: [FolderBreadcrumb] = []
    private var hasLoadedMeta = false

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let browseService: (any AdvancedLibraryBrowseService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let browseSession: LibraryBrowseSession
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let preferencesKey: String
    private let pageSize = 40

    init(
        library: Library,
        services: MediaServices,
        settingsManager: SettingsManager,
        browseSession: LibraryBrowseSession,
    ) {
        self.library = library
        advancedService = services.library as? any PlexAdvancedLibraryService
        browseService = services.library as? any AdvancedLibraryBrowseService
        service = services.library
        self.settingsManager = settingsManager
        self.browseSession = browseSession
        preferencesKey = LibraryBrowsePreferences.key(
            scopeID: services.serverPreferencesScopeID,
            libraryID: library.id,
        )
        let preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        layout = preferences.resolvedLayout(
            for: library.type,
            defaultLayout: settingsManager.interface.libraryDefaultLayout,
        )
        showsFolderTree = preferences.showsFolderTree ?? false
        browseSession.restoreQueryIfNeeded(preferences.jellyfinQuery)
        controls = LibraryBrowseControlsViewModel(
            advancedService: services.library as? any PlexAdvancedLibraryService,
            browseService: services.library as? any AdvancedLibraryBrowseService,
            library: library,
            browseSession: browseSession,
            pendingRestore: preferences.plex,
        )
        controls.onSelectionChanged = { [weak self] in
            self?.savePreferences()
            self?.selectionChanged()
        }
        controls.onDisplayTypeChanged = { [weak self] in
            guard let self else { return }
            savePreferences()
            folderStack = []
            Task { await self.refresh() }
        }
        controls.onSelectionReset = { [weak self] in
            self?.clearSavedSelection()
            self?.selectionChanged()
        }
        browseSession.externalQueryChangeHandler = { [weak self] in
            self?.savePreferences()
            self?.selectionChanged()
        }
    }

    var canNavigateBack: Bool {
        !folderStack.isEmpty
    }

    var folderPath: String {
        folderStack.map(\.id).joined(separator: "/")
    }

    var showsCharacterColumn: Bool {
        folderTree == nil && supportsSectionCharacters && !sectionCharacters.isEmpty
    }

    var canShowFolderTree: Bool {
        advancedService != nil && controls.isFolderDisplayType
    }

    var isFolderTreeActive: Bool {
        showsFolderTree && canShowFolderTree
    }

    func toggleFolderTree() {
        showsFolderTree.toggle()
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        preferences.showsFolderTree = showsFolderTree ? true : nil
        settingsManager.setLibraryBrowsePreferences(preferences, for: preferencesKey)
        Task { await refresh() }
    }

    func load() async {
        guard itemsByIndex.isEmpty, folderTree == nil else { return }
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

    func removeDeletedItems(ids: Set<String>) {
        folderTree?.removeMedia(ids: ids)
        let removed = itemsByIndex.compactMap { index, item -> Int? in
            guard case let .media(media) = item, ids.contains(media.id) else { return nil }
            return index
        }
        guard !removed.isEmpty else { return }
        var shifted: [Int: LibraryBrowseItem] = [:]
        for (index, item) in itemsByIndex where !removed.contains(index) {
            shifted[index - removed.count(where: { $0 < index })] = item
        }
        itemsByIndex = shifted
        totalItemCount = max(totalItemCount - removed.count, 0)
        sectionCharacters = Self.sections(sectionCharacters, removingIndexes: removed)
        // Every page past a removal now starts one item later on the server, so pages load again when shown.
        loadedPageStarts.removeAll()
    }

    /// Removed indexes are those before the shift; sections left empty are dropped.
    static func sections(_ sections: [SectionCharacter], removingIndexes removed: [Int]) -> [SectionCharacter] {
        var runningIndex = 0
        return sections.compactMap { section in
            let end = section.startIndex + section.size
            let size = section.size - removed.count(where: { $0 >= section.startIndex && $0 < end })
            guard size > 0 else { return nil }
            defer { runningIndex += size }
            return SectionCharacter(
                id: "\(section.title)-\(runningIndex)",
                title: section.title,
                size: size,
                startIndex: runningIndex,
            )
        }
    }

    func refresh() async {
        scrollResetID &+= 1
        resetState()
        folderTree = nil
        // Meta decides whether the selected display type is a folder listing, so it is fetched first.
        if !(hasLoadedMeta && isFolderTreeActive) {
            isLoading = true
            await loadPage(start: 0)
            isLoading = false
        }
        if isFolderTreeActive {
            await reloadFolderTree()
        } else {
            await fetchCharactersIfNeeded()
        }
    }

    private func reloadFolderTree() async {
        guard let advancedService, let browsePath = library.plexBrowsePath else { return }
        let includeCollections = settingsManager.interface.displayCollections ? true : nil
        let tree =
            FolderTreeModel(rootEndpoint: resolvedEndpoint(
                browsePath: browsePath,
            )) { [controls] endpoint, start, limit in
                try await advancedService.advancedBrowse(
                    path: endpoint.path,
                    queryItems: controls.buildQueryItems(
                        baseItems: endpoint.queryItems,
                        includeCollections: includeCollections,
                        includeMeta: false,
                    ),
                    startIndex: start,
                    limit: limit,
                )
            }
        folderTree = tree
        await tree.loadRoot()
    }

    func setLayout(_ layout: LibraryBrowseLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        preferences.setLayout(
            layout,
            for: library.type,
            defaultLayout: settingsManager.interface.libraryDefaultLayout,
        )
        settingsManager.setLibraryBrowsePreferences(preferences, for: preferencesKey)
    }

    /// Skipped while server controls are hidden, so a degraded offline state never overwrites the saved selection.
    private func savePreferences() {
        guard controls.hasControls else { return }
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        if advancedService != nil {
            preferences.plex = controls.plexSelection
        } else if browseService != nil {
            preferences.jellyfinQuery = browseSession.query
        }
        settingsManager.setLibraryBrowsePreferences(preferences, for: preferencesKey)
    }

    private func clearSavedSelection() {
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        preferences.plex = controls.selectedDisplayType.map {
            LibraryBrowsePreferences.PlexSelection(displayTypeKey: $0.key)
        }
        preferences.jellyfinQuery = nil
        settingsManager.setLibraryBrowsePreferences(preferences, for: preferencesKey)
    }

    private func selectionChanged() {
        guard browseService != nil else {
            Task { await refresh() }
            return
        }
        refreshTask?.cancel()
        refreshTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            await self?.refresh()
        }
    }

    private func fetchCharactersIfNeeded() async {
        guard let advancedService, sectionCharacters.isEmpty, supportsSectionCharacters,
              let browsePath = library.plexBrowsePath else { return }
        do {
            let endpoint = resolvedEndpoint(browsePath: browsePath)
            guard let firstCharacterEndpoint = firstCharacterEndpoint(from: endpoint) else { return }
            let includeCollections = settingsManager.interface.displayCollections ? true : nil
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: false,
            )

            let values = try await advancedService.sectionCharacters(
                path: firstCharacterEndpoint.path,
                queryItems: queryItems,
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
        guard let browsePath = library.plexBrowsePath else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        errorMessage = nil
        loadingPageStarts.insert(start)
        defer {
            loadingPageStarts.remove(start)
        }

        do {
            let endpoint = resolvedEndpoint(browsePath: browsePath)
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
                limit: pageSize,
            )

            if includeMeta, let meta = response.meta {
                let restoreChanged = controls.applyMeta(meta)
                hasLoadedMeta = true
                if restoreChanged {
                    savePreferences()
                    Task { await refresh() }
                }
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
            let requestedQuery = browseSession.query
            let page: MediaPage<MediaDisplayItem> = if let browseService {
                try await browseService.browseItems(
                    in: library,
                    parentID: nil,
                    query: requestedQuery,
                    startIndex: start,
                    limit: pageSize,
                )
            } else {
                try await service.items(
                    in: library,
                    parentID: nil,
                    startIndex: start,
                    limit: pageSize,
                )
            }
            guard !Task.isCancelled, browseService == nil || requestedQuery == browseSession.query else { return }
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

    private func resolvedEndpoint(browsePath: String) -> PlexEndpoint {
        if let currentFolderEndpoint {
            return currentFolderEndpoint
        }
        if let displayTypeKey = controls.requestedDisplayTypeKey,
           let endpoint = PlexEndpoint(key: displayTypeKey)
        {
            return endpoint
        }

        let queryItems = [URLQueryItem.make("type", defaultTypeQueryValue)].compactMap(\.self)
        return PlexEndpoint(path: browsePath, queryItems: queryItems)
    }

    private var currentFolderEndpoint: PlexEndpoint? {
        folderStack.last?.endpoint
    }

    private var defaultTypeQueryValue: String? {
        if library.isShared {
            return PlexSharedLibrary.videoTypes
        }
        return switch library.type {
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
        // The shared view answers with no characters.
        guard advancedService != nil, !library.isShared, let browsePath = library.plexBrowsePath else { return false }
        let endpoint = resolvedEndpoint(browsePath: browsePath)
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
