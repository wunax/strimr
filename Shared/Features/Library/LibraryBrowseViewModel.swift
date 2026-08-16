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
    private var folderStack: [FolderBreadcrumb] = []

    private var reachedEnd = false
    private var hasLoadedMeta = false

    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let browseService: (any AdvancedLibraryBrowseService)?
    @ObservationIgnored private let service: any MediaLibraryService
    @ObservationIgnored private let settingsManager: SettingsManager
    @ObservationIgnored private let browseSession: LibraryBrowseSession
    @ObservationIgnored private var refreshTask: Task<Void, Never>?

    init(
        library: Library,
        services: MediaServices,
        settingsManager: SettingsManager,
        browseSession: LibraryBrowseSession
    ) {
        self.library = library
        advancedService = services.library as? any PlexAdvancedLibraryService
        browseService = services.library as? any AdvancedLibraryBrowseService
        service = services.library
        self.settingsManager = settingsManager
        self.browseSession = browseSession
        controls = LibraryBrowseControlsViewModel(
            advancedService: services.library as? any PlexAdvancedLibraryService,
            browseService: services.library as? any AdvancedLibraryBrowseService,
            library: library,
            browseSession: browseSession
        )
        controls.onSelectionChanged = { [weak self] in
            self?.selectionChanged()
        }
        controls.onDisplayTypeChanged = { [weak self] in
            guard let self else { return }
            folderStack = []
            Task { await self.refresh() }
        }
        browseSession.externalQueryChangeHandler = { [weak self] in
            self?.selectionChanged()
        }
    }

    var canNavigateBack: Bool {
        !folderStack.isEmpty
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
        await fetch(reset: true)
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

    private func fetch(reset: Bool) async {
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
                limit: 20
            )

            if includeMeta, let meta = response.meta {
                controls.applyMeta(meta)
                hasLoadedMeta = true
            }

            let newItems = response.items
            let total = response.totalCount

            if reset {
                browseItems = newItems
            } else {
                browseItems.append(contentsOf: newItems)
            }

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
        if reset { isLoading = true } else { isLoadingMore = true }
        errorMessage = nil
        defer {
            isLoading = false
            isLoadingMore = false
        }
        do {
            let start = reset ? 0 : browseItems.count
            let requestedQuery = browseSession.query
            let page: MediaPage<MediaDisplayItem>
            if let browseService {
                page = try await browseService.browseItems(
                    in: library,
                    parentID: folderStack.last?.id,
                    query: requestedQuery,
                    startIndex: start,
                    limit: 20
                )
            } else {
                page = try await service.items(
                    in: library,
                    parentID: folderStack.last?.id,
                    startIndex: start,
                    limit: 20
                )
            }
            guard !Task.isCancelled, browseService == nil || requestedQuery == browseSession.query else { return }
            let newItems = page.items.map(LibraryBrowseItem.media)
            if reset { browseItems = newItems } else { browseItems.append(contentsOf: newItems) }
            reachedEnd = page.totalCount.map { browseItems.count >= $0 } ?? newItems.isEmpty
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            if reset { resetState(error: error.localizedDescription) } else { errorMessage = error.localizedDescription }
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

    private func resetState(error: String? = nil) {
        browseItems = []
        errorMessage = error
        isLoading = false
        isLoadingMore = false
        reachedEnd = false
    }
}
