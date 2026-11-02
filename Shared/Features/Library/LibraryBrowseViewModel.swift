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
    private(set) var itemsByIndex: [Int: LibraryBrowseItem] = [:]
    /// Every position gets a placeholder, so the grid has its full height and any position can be scrolled to.
    private(set) var totalItemCount = 0
    /// False when the server does not report the listing size; `totalItemCount` is then only an estimate.
    private(set) var isTotalKnown = false
    private(set) var sectionIndex: LibrarySectionIndex?
    var isLoading = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel
    var scrollResetID = 0
    private(set) var layout: LibraryBrowseLayout
    /// The user's choice for the downloads filter; `nil` follows the connection.
    private var downloadedOnlyChoice: Bool?
    private(set) var hasDownloads = false
    private(set) var showsFolderTree: Bool
    private(set) var folderTree: FolderTreeModel?
    private var folderStack: [FolderBreadcrumb] = []

    private var hasLoadedMeta = false
    @ObservationIgnored private var pages = LibraryBrowsePageTracker(pageSize: 40)
    @ObservationIgnored private var scrubThrottle = LibraryScrubLoadThrottle()
    @ObservationIgnored private var isScrubbing = false

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let browseService: (any AdvancedLibraryBrowseService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let browseSession: LibraryBrowseSession
    @ObservationIgnored private var refreshTask: Task<Void, Never>?
    @ObservationIgnored private let preferencesKey: String
    @ObservationIgnored private let owner: MediaOwner

    init(
        library: Library,
        services: MediaServices,
        settingsManager: SettingsManager,
        browseSession: LibraryBrowseSession,
    ) {
        self.library = library
        owner = services.owner
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

    /// Server-side sort and filters cannot run offline; only the local title order is available.
    var isServerUnreachable: Bool {
        OfflineCoordinator.shared.isUnreachable(owner.server)
    }

    /// Switches the data source to the local downloads of this library. Offline, it is on by default since only
    /// downloads can be played.
    var isDownloadedOnly: Bool {
        downloadedOnlyChoice ?? (isServerUnreachable && hasDownloads)
    }

    /// Hidden in libraries without downloads, but kept while active so it can always be turned off.
    var showsDownloadedOnlyToggle: Bool {
        hasDownloads || isDownloadedOnly
    }

    var activeFilterCount: Int {
        (isDownloadedOnly ? 1 : 0) + (showsServerControls ? controls.activeFilters.count : 0)
    }

    var showsFiltersButton: Bool {
        showsDownloadedOnlyToggle || (controls.hasControls && controls.showsFilterControl)
    }

    var viewMode: LibraryBrowseViewMode {
        isFolderTreeActive ? .tree : LibraryBrowseViewMode(layout: layout)
    }

    var viewModes: [LibraryBrowseViewMode] {
        canShowFolderTree ? [.grid, .list, .tree] : [.grid, .list]
    }

    var showsServerControls: Bool {
        controls.hasControls && !isDownloadedOnly && !isServerUnreachable
    }

    var canShowFolderTree: Bool {
        advancedService != nil && controls.isFolderDisplayType && !isDownloadedOnly && !isServerUnreachable
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

    func setDownloadedOnly(_ isOn: Bool) {
        guard isOn != isDownloadedOnly else { return }
        downloadedOnlyChoice = isOn
        folderStack = []
        Task { await refresh() }
    }

    var serverFilters: LibraryBrowseFiltersView.ServerFilters {
        if isServerUnreachable {
            return .unreachable
        }
        return isDownloadedOnly ? .downloads : .available
    }

    var downloadsFilter: LibraryBrowseControlsViewModel.ActiveFilter? {
        guard isDownloadedOnly else { return nil }
        return .init(id: "downloadedOnly", title: String(localized: "offline.library.downloadedOnly")) { [weak self] in
            self?.setDownloadedOnly(false)
        }
    }

    var canResetFilters: Bool {
        downloadedOnlyChoice != nil || (showsServerControls && controls.canResetSelection)
    }

    func resetFilters() {
        let resetsServerSelection = showsServerControls && controls.canResetSelection
        downloadedOnlyChoice = nil
        if resetsServerSelection {
            controls.resetSelection()
        } else {
            folderStack = []
            Task { await refresh() }
        }
    }

    func connectionChanged() {
        downloadedOnlyChoice = nil
        Task { await refresh() }
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

    /// Size shown next to the controls; unknown while the server has not reported it.
    var itemCount: Int? {
        isTotalKnown ? totalItemCount : nil
    }

    var visibleSectionIndex: LibrarySectionIndex? {
        guard let sectionIndex, sectionIndex.isUsable, folderTree == nil, !isDownloadedOnly, !isServerUnreachable,
              controls.isPlexTitleSort else { return nil }
        return sectionIndex
    }

    var canScrub: Bool {
        folderTree == nil && isTotalKnown && totalItemCount > 0
    }

    func load() async {
        guard totalItemCount == 0, folderTree == nil else { return }
        await loadFirstPage()
        if isFolderTreeActive, folderTree == nil {
            await reloadFolderTree()
        } else {
            await loadSectionIndexIfNeeded()
        }
    }

    func itemAppeared(at index: Int) {
        guard !isScrubbing else { return }
        Task { await loadPagesAround(index: index) }
    }

    func jump(to section: LibrarySectionIndex.Section) {
        Task { await loadPagesAround(index: section.startIndex) }
    }

    func beginScrubbing() {
        isScrubbing = true
        scrubThrottle.reset()
    }

    func scrub(to index: Int) {
        guard isScrubbing, scrubThrottle.shouldLoad(at: .now) else { return }
        let start = pages.pageStart(for: index)
        Task { await loadPage(start: start) }
    }

    func endScrubbing(at index: Int) {
        isScrubbing = false
        Task { await loadPagesAround(index: index) }
    }

    func loadPagesAround(index: Int) async {
        let starts = pages.pagesToLoad(
            around: index,
            totalCount: totalItemCount > 0 ? totalItemCount : nil,
            isIndexLoaded: itemsByIndex[index] != nil,
        )
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
        // Every page past a removal now starts earlier on the server, so pages load again when shown.
        pages.invalidateLoaded()
    }

    func refresh() async {
        scrollResetID &+= 1
        resetItems()
        folderTree = nil
        // Meta decides whether the selected display type is a folder listing, so it is fetched first.
        if !(hasLoadedMeta && isFolderTreeActive) {
            await loadFirstPage()
        }
        if isFolderTreeActive {
            await reloadFolderTree()
        } else {
            await loadSectionIndexIfNeeded()
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
        guard showsServerControls else { return }
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

    private func downloadedLibraryItems() -> [MediaDisplayItem] {
        OfflineCoordinator.shared.store?.downloadedLibraryItems(libraryID: library.id, owner: owner) ?? []
    }

    private func loadFirstPage() async {
        let downloadedItems = downloadedLibraryItems()
        hasDownloads = !downloadedItems.isEmpty
        if isDownloadedOnly {
            for (index, item) in downloadedItems.enumerated() {
                itemsByIndex[index] = .media(item)
            }
            totalItemCount = downloadedItems.count
            isTotalKnown = true
            errorMessage = nil
            return
        }
        if advancedService != nil, library.plexBrowsePath == nil {
            resetItems(error: String(localized: "errors.missingLibraryIdentifier"))
            return
        }
        isLoading = true
        await loadPage(start: 0)
        isLoading = false
    }

    private func loadPage(start: Int) async {
        guard !isDownloadedOnly, pages.begin(start) else { return }
        let generation = scrollResetID
        var loaded = false
        defer {
            // A refresh in the meantime already reset the tracker.
            if generation == scrollResetID {
                pages.finish(start, loaded: loaded)
            }
        }
        errorMessage = nil
        if let advancedService {
            loaded = await loadPlexPage(start: start, generation: generation, service: advancedService)
        } else {
            loaded = await loadCommonPage(start: start, generation: generation)
        }
    }

    private func loadPlexPage(
        start: Int,
        generation: Int,
        service advancedService: any PlexAdvancedLibraryService,
    ) async -> Bool {
        guard let browsePath = library.plexBrowsePath else { return false }
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

            store(response.items, at: start, reportedTotal: response.totalCount)
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
                    parentID: folderStack.last?.id,
                    query: requestedQuery,
                    startIndex: start,
                    limit: pages.pageSize,
                )
            } else {
                try await service.items(
                    in: library,
                    parentID: folderStack.last?.id,
                    startIndex: start,
                    limit: pages.pageSize,
                )
            }
            guard !Task.isCancelled, generation == scrollResetID,
                  browseService == nil || requestedQuery == browseSession.query else { return false }
            store(page.items.map(LibraryBrowseItem.media), at: start, reportedTotal: page.totalCount)
            return true
        } catch {
            guard !error.isCancellation, generation == scrollResetID else { return false }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
            return false
        }
    }

    private func store(_ items: [LibraryBrowseItem], at start: Int, reportedTotal: Int?) {
        for (offset, item) in items.enumerated() {
            itemsByIndex[start + offset] = item
        }
        if let reportedTotal {
            isTotalKnown = true
            totalItemCount = reportedTotal
        } else {
            isTotalKnown = false
            totalItemCount = LibraryBrowsePageTracker.estimatedTotal(
                current: totalItemCount,
                start: start,
                received: items.count,
                pageSize: pages.pageSize,
            )
        }
    }

    private func loadSectionIndexIfNeeded() async {
        guard let advancedService, sectionIndex == nil, supportsSectionIndex,
              let browsePath = library.plexBrowsePath else { return }
        let endpoint = resolvedEndpoint(browsePath: browsePath)
        guard let firstCharacterEndpoint = firstCharacterEndpoint(from: endpoint) else { return }
        let generation = scrollResetID
        do {
            let includeCollections = settingsManager.interface.displayCollections ? true : nil
            let queryItems = controls.buildQueryItems(
                baseItems: endpoint.queryItems,
                includeCollections: includeCollections,
                includeMeta: false,
            )
            let characters = try await advancedService.sectionCharacters(
                path: firstCharacterEndpoint.path,
                queryItems: queryItems,
            )
            guard generation == scrollResetID else { return }
            sectionIndex = LibrarySectionIndex(characters: characters)
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    /// The shared view answers with no characters, and other sorts get a single `#` section.
    private var supportsSectionIndex: Bool {
        guard advancedService != nil, !library.isShared, !isDownloadedOnly, !isServerUnreachable,
              controls.isPlexTitleSort, let browsePath = library.plexBrowsePath else { return false }
        return firstCharacterEndpoint(from: resolvedEndpoint(browsePath: browsePath)) != nil
    }

    private func firstCharacterEndpoint(from endpoint: PlexEndpoint) -> PlexEndpoint? {
        let components = endpoint.path.split(separator: "/")
        guard components.last == "all" else { return nil }
        let prefix = components.dropLast().joined(separator: "/")
        return PlexEndpoint(path: "/\(prefix)/firstCharacter", queryItems: endpoint.queryItems)
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

    private func resetItems(error: String? = nil) {
        itemsByIndex = [:]
        totalItemCount = 0
        isTotalKnown = false
        sectionIndex = nil
        errorMessage = error
        isLoading = false
        pages.reset()
    }
}
