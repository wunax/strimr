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
    var browseItems: [LibraryBrowseItem] = []
    var isLoading = false
    var isLoadingMore = false
    var errorMessage: String?
    var controls: LibraryBrowseControlsViewModel
    var scrollResetID = 0
    private(set) var layout: LibraryBrowseLayout
    /// Server-reported size of the current listing, or the local count in downloads-only mode.
    private(set) var totalCount: Int?
    /// Switches the data source to the local downloads of this library, online or offline.
    private(set) var isDownloadedOnly = false
    private(set) var hasDownloads = false
    private var folderStack: [FolderBreadcrumb] = []

    private var reachedEnd = false
    private var hasLoadedMeta = false

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
            scopeID: services.homeRowPreferencesScopeID,
            libraryID: library.id,
        )
        let preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        layout = preferences.resolvedLayout(for: library.type)
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

    /// Hidden in libraries without downloads, but kept while active so it can always be turned off.
    var showsDownloadedOnlyToggle: Bool {
        hasDownloads || isDownloadedOnly
    }

    var showsServerControls: Bool {
        controls.hasControls && !isDownloadedOnly && !isServerUnreachable
    }

    func toggleDownloadedOnly() {
        isDownloadedOnly.toggle()
        folderStack = []
        Task { await refresh() }
    }

    func load() async {
        guard browseItems.isEmpty else { return }
        await fetch(reset: true)
    }

    func loadMore() async {
        guard !isLoading, !isLoadingMore, !reachedEnd else { return }
        await fetch(reset: false)
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
        scrollResetID &+= 1
        reachedEnd = false
        browseItems = []
        totalCount = nil
        await fetch(reset: true)
    }

    func setLayout(_ layout: LibraryBrowseLayout) {
        guard layout != self.layout else { return }
        self.layout = layout
        var preferences = settingsManager.libraryBrowsePreferences(for: preferencesKey)
        preferences.layout = layout
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

    private func fetch(reset: Bool) async {
        let downloadedItems = reset ? downloadedLibraryItems() : []
        if reset {
            hasDownloads = !downloadedItems.isEmpty
        }
        if isDownloadedOnly {
            guard reset else { return }
            browseItems = downloadedItems.map(LibraryBrowseItem.media)
            totalCount = browseItems.count
            errorMessage = nil
            reachedEnd = true
            return
        }
        guard let advancedService else {
            await fetchUsingCommonService(reset: reset)
            return
        }
        guard let sectionId = library.sectionId else {
            resetState(error: String(localized: "errors.missingLibraryIdentifier"))
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
            let start = reset ? 0 : browseItems.count
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
                limit: 20,
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

            if reset {
                browseItems = newItems
            } else {
                browseItems.append(contentsOf: newItems)
            }

            totalCount = total
            reachedEnd = browseItems.count >= total || newItems.isEmpty
        } catch {
            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func fetchUsingCommonService(reset: Bool) async {
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
            let start = reset ? 0 : browseItems.count
            let requestedQuery = browseSession.query
            let page: MediaPage<MediaDisplayItem> = if let browseService {
                try await browseService.browseItems(
                    in: library,
                    parentID: folderStack.last?.id,
                    query: requestedQuery,
                    startIndex: start,
                    limit: 20,
                )
            } else {
                try await service.items(
                    in: library,
                    parentID: folderStack.last?.id,
                    startIndex: start,
                    limit: 20,
                )
            }
            guard !Task.isCancelled, browseService == nil || requestedQuery == browseSession.query else { return }
            let newItems = page.items.map(LibraryBrowseItem.media)
            if reset {
                browseItems = newItems
            } else {
                browseItems.append(contentsOf: newItems)
            }
            totalCount = page.totalCount
            reachedEnd = page.totalCount.map { browseItems.count >= $0 } ?? newItems.isEmpty
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if reset {
                resetState(error: error.localizedDescription)
            } else {
                errorMessage = error.localizedDescription
            }
        }
    }

    private func resolvedEndpoint(sectionId: Int) -> PlexEndpoint {
        if let currentFolderEndpoint {
            return currentFolderEndpoint
        }
        if let displayTypeKey = controls.requestedDisplayTypeKey,
           let endpoint = PlexEndpoint(key: displayTypeKey)
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

    private func resetState(error: String? = nil) {
        browseItems = []
        totalCount = nil
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }
}
