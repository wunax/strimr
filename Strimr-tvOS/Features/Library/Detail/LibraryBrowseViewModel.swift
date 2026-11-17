import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseViewModel {
    private struct FolderBreadcrumb: Identifiable, Equatable {
        let id: String
        let title: String
        let endpoint: PlexEndpoint
    }

    let library: Library
    var itemsByIndex: [Int: LibraryBrowseItem] = [:]
    var totalItemCount = 0
    var sectionIndex: LibrarySectionIndex?
    var isLoading = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel
    var scrollResetID = 0
    private(set) var layout: LibraryBrowseLayout
    private(set) var showsFolderTree: Bool
    private(set) var folderTree: FolderTreeModel?

    @ObservationIgnored private var pages = LibraryBrowsePageTracker(pageSize: 40)
    private var folderStack: [FolderBreadcrumb] = []
    private var hasLoadedMeta = false

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let browseService: (any AdvancedLibraryBrowseService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let browseSession: LibraryBrowseSession
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let preferencesKey: String

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
        folderTree == nil && supportsSectionCharacters && sectionIndex?.isUsable == true
    }

    var canShowFolderTree: Bool {
        advancedService != nil && controls.isFolderDisplayType
    }

    var isFolderTreeActive: Bool {
        showsFolderTree && canShowFolderTree
    }

    var viewMode: LibraryBrowseViewMode {
        isFolderTreeActive ? .tree : LibraryBrowseViewMode(layout: layout)
    }

    var viewModes: [LibraryBrowseViewMode] {
        canShowFolderTree ? [.grid, .list, .tree] : [.grid, .list]
    }

    func setViewMode(_ mode: LibraryBrowseViewMode) {
        switch mode {
        case .tree:
            if !isFolderTreeActive {
                toggleFolderTree()
            }
        case .grid, .list:
            setLayout(mode == .grid ? .grid : .list)
            if isFolderTreeActive {
                toggleFolderTree()
            }
        }
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

    /// Called for every card that appears, so it only starts a task when a page is actually missing.
    func itemAppeared(at index: Int) {
        let starts = pagesToLoad(around: index)
        guard !starts.isEmpty else { return }
        Task { await loadPages(starts) }
    }

    func loadPagesAround(index: Int) async {
        await loadPages(pagesToLoad(around: index))
    }

    private func pagesToLoad(around index: Int) -> [Int] {
        pages.pagesToLoad(
            around: index,
            totalCount: totalItemCount > 0 ? totalItemCount : nil,
            isIndexLoaded: itemsByIndex[index] != nil,
        )
    }

    private func loadPages(_ starts: [Int]) async {
        for start in starts {
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
        sectionIndex = sectionIndex?.removingIndexes(removed)
        // Every page past a removal now starts one item later on the server, so pages load again when shown.
        pages.invalidateLoaded()
    }

    func refresh() async {
        scrollResetID &+= 1
        let generation = scrollResetID
        resetState()
        folderTree = nil
        // Meta decides whether the selected display type is a folder listing, so it is fetched first.
        if !(hasLoadedMeta && isFolderTreeActive) {
            isLoading = true
            await loadPage(start: 0)
            // A newer refresh owns the loading state and the rest of the work.
            guard generation == scrollResetID else { return }
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
        guard let advancedService, sectionIndex == nil, supportsSectionCharacters,
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
            let index = LibrarySectionIndex(characters: values)
            sectionIndex = index
            totalItemCount = max(totalItemCount, index.sections.reduce(0) { $0 + $1.size })
        } catch {
            if itemsByIndex.isEmpty {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func loadPage(start: Int) async {
        if advancedService != nil, library.plexBrowsePath == nil {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        guard pages.begin(start) else { return }
        let generation = scrollResetID
        var loaded = false
        defer {
            // A refresh in the meantime already reset the tracker.
            if generation == scrollResetID {
                pages.finish(start, loaded: loaded)
            }
        }
        clearError()
        if let advancedService, let browsePath = library.plexBrowsePath {
            loaded = await loadPlexPage(
                start: start,
                browsePath: browsePath,
                generation: generation,
                service: advancedService,
            )
        } else {
            loaded = await loadCommonPage(start: start, generation: generation)
        }
    }

    private func loadPlexPage(
        start: Int,
        browsePath: String,
        generation: Int,
        service advancedService: any PlexAdvancedLibraryService,
    ) async -> Bool {
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
                limit: pages.pageSize,
            )
            guard generation == scrollResetID else { return false }

            if includeMeta, let meta = response.meta {
                let restoreChanged = controls.applyMeta(meta)
                hasLoadedMeta = true
                if restoreChanged {
                    savePreferences()
                    Task { await refresh() }
                }
            }

            store(response.items, at: start, total: max(totalItemCount, response.totalCount))
            return true
        } catch {
            guard !error.isCancellation, generation == scrollResetID else { return false }
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func loadCommonPage(start: Int, generation: Int) async -> Bool {
        do {
            let requestedQuery = browseSession.query
            let page: MediaPage<MediaDisplayItem> = if let browseService {
                try await browseService.browseItems(
                    in: library,
                    parentID: nil,
                    query: requestedQuery,
                    startIndex: start,
                    limit: pages.pageSize,
                )
            } else {
                try await service.items(
                    in: library,
                    parentID: nil,
                    startIndex: start,
                    limit: pages.pageSize,
                )
            }
            guard !Task.isCancelled, generation == scrollResetID,
                  browseService == nil || requestedQuery == browseSession.query else { return false }
            store(
                page.items.map(LibraryBrowseItem.media),
                at: start,
                total: page.totalCount ?? (start + page.items.count),
            )
            return true
        } catch {
            guard !error.isCancellation, generation == scrollResetID else { return false }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
            return false
        }
    }

    /// One mutation per page: inserting item by item invalidated every visible card once per item, and
    /// Observation notifies on every assignment, even of an unchanged count.
    private func store(_ items: [LibraryBrowseItem], at start: Int, total: Int) {
        let page = Dictionary(uniqueKeysWithValues: items.enumerated().map { (start + $0.offset, $0.element) })
        itemsByIndex.merge(page) { _, new in new }
        if totalItemCount != total {
            totalItemCount = total
        }
    }

    private func clearError() {
        if errorMessage != nil {
            errorMessage = nil
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
        guard advancedService != nil, !library.isShared, controls.isPlexTitleSort,
              let browsePath = library.plexBrowsePath else { return false }
        let endpoint = resolvedEndpoint(browsePath: browsePath)
        return firstCharacterEndpoint(from: endpoint) != nil
    }

    private func resetState(error: String? = nil) {
        itemsByIndex = [:]
        totalItemCount = 0
        sectionIndex = nil
        errorMessage = error
        isLoading = false
        pages.reset()
    }
}
