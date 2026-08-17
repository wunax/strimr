import Foundation
import Observation

@MainActor
@Observable
final class LibraryBrowseControlsViewModel {
    enum Panel: Hashable {
        case type
        case filters
        case sort
    }

    struct DisplayType: Identifiable, Equatable {
        let id: String
        let key: String
        let type: MediaKind
        let title: String
        let isActive: Bool
        let filters: [PlexSectionItemFilter]
        let sorts: [PlexSectionItemSort]

        init(metaType: PlexSectionItemMetaType) {
            id = metaType.key
            key = metaType.key
            type = metaType.type.mediaKind
            title = metaType.title
            isActive = metaType.active ?? false
            filters = metaType.filter ?? []
            sorts = metaType.sort ?? []
        }
    }

    struct SortSelection: Equatable {
        let sort: PlexSectionItemSort
        let direction: PlexSortDirection
    }

    struct FilterOption: Identifiable, Equatable {
        let id: String
        let key: String
        let title: String
        let fastKey: String?

        init(directory: PlexFilterDirectory) {
            id = directory.fastKey ?? directory.key
            key = directory.key
            title = directory.title
            fastKey = directory.fastKey
        }
    }

    struct FilterSelection: Equatable {
        let filter: PlexSectionItemFilter
        let isEnabled: Bool
        let selectedOption: FilterOption?
    }

    struct FilterSheetState: Identifiable, Equatable {
        let filter: PlexSectionItemFilter

        var id: String {
            filter.filter
        }
    }

    enum JellyfinFilter: String, CaseIterable, Identifiable {
        case watchStatus
        case inProgress
        case favorites
        case genres
        case years

        var id: String {
            rawValue
        }

        var title: String {
            switch self {
            case .watchStatus:
                String(localized: "library.browse.filters.watchStatus")
            case .inProgress:
                String(localized: "library.browse.filters.inProgress")
            case .favorites:
                String(localized: "library.browse.filters.favorites")
            case .genres:
                String(localized: "library.browse.filters.genres")
            case .years:
                String(localized: "library.browse.filters.years")
            }
        }

        var isBoolean: Bool {
            self == .inProgress || self == .favorites
        }

        var supportsMultiple: Bool {
            self == .genres || self == .years
        }
    }

    struct JellyfinSortOption: Identifiable, Equatable {
        let id: LibraryBrowseSort
        let title: String
        let defaultDirection: LibraryBrowseSortDirection
    }

    var displayTypes: [DisplayType] = []
    var selectedDisplayType: DisplayType?
    var activePanel: Panel?
    var selectedSort: SortSelection?
    var selectedFilters: [String: FilterSelection] = [:]
    var activeFilterSheet: FilterSheetState?
    var activeJellyfinFilterSheet: JellyfinFilter?
    var jellyfinFilterOptions = LibraryBrowseFilterOptions()
    var isLoadingJellyfinFilterOptions = false
    var jellyfinFilterOptionsError: String?
    var filterOptions: [String: [FilterOption]] = [:]
    var filterOptionsLoading: Set<String> = []
    var filterOptionsError: [String: String] = [:]

    @ObservationIgnored var onSelectionChanged: (() -> Void)?
    @ObservationIgnored var onDisplayTypeChanged: (() -> Void)?
    @ObservationIgnored private let advancedService: (any PlexAdvancedLibraryService)?
    @ObservationIgnored private let browseService: (any AdvancedLibraryBrowseService)?
    @ObservationIgnored private let library: Library?
    @ObservationIgnored private let browseSession: LibraryBrowseSession?

    init(
        advancedService: (any PlexAdvancedLibraryService)?,
        browseService: (any AdvancedLibraryBrowseService)? = nil,
        library: Library? = nil,
        browseSession: LibraryBrowseSession? = nil,
    ) {
        self.advancedService = advancedService
        self.browseService = browseService
        self.library = library
        self.browseSession = browseSession
    }

    var isJellyfinBrowse: Bool {
        browseService != nil && (library?.type == .movie || library?.type == .series)
    }

    var hasControls: Bool {
        hasDisplayTypes || isJellyfinBrowse
    }

    var hasDisplayTypes: Bool {
        !displayTypes.isEmpty
    }

    var availableFilters: [PlexSectionItemFilter] {
        selectedDisplayType?.filters ?? []
    }

    var availableSorts: [PlexSectionItemSort] {
        selectedDisplayType?.sorts ?? []
    }

    var showsFilterPill: Bool {
        isJellyfinBrowse || !availableFilters.isEmpty
    }

    var showsSortPill: Bool {
        isJellyfinBrowse || !availableSorts.isEmpty
    }

    var typePillTitle: String {
        selectedDisplayType?.title ?? String(localized: "library.browse.type.title")
    }

    var filterPillTitle: String {
        let base = String(localized: "library.browse.filters.title")
        if isJellyfinBrowse {
            let count = jellyfinActiveFilterCount
            return count == 0 ? base : String(localized: "library.browse.filters.count \(count)")
        }
        let summaries = activeFilterSummaries()
        guard !summaries.isEmpty else { return base }
        if summaries.count <= 2 {
            return base + " · " + summaries.joined(separator: ", ")
        }
        return String(localized: "library.browse.filters.count \(summaries.count)")
    }

    var sortPillTitle: String {
        let base = String(localized: "library.browse.sort.title")
        if isJellyfinBrowse, let option = jellyfinSortOptions.first(where: { $0.id == browseSession?.query.sort }) {
            let direction = browseSession?.query.sortDirection ?? .ascending
            return base + " · " + option.title + " · " + jellyfinSortDirectionLabel(direction)
        }
        guard let selectedSort else { return base }
        let directionLabel = sortDirectionLabel(for: selectedSort.direction)
        return base + " · " + selectedSort.sort.title + " · " + directionLabel
    }

    var jellyfinSortOptions: [JellyfinSortOption] {
        guard let library else { return [] }
        var values = [
            jellyfinSortOption(.name, "library.browse.sort.name", .ascending),
            jellyfinSortOption(.releaseDate, "library.browse.sort.releaseDate", .descending),
            jellyfinSortOption(.dateAdded, "library.browse.sort.dateAdded", .descending),
            jellyfinSortOption(.rating, "library.browse.sort.rating", .descending),
        ]
        if library.type == .series {
            values.append(jellyfinSortOption(.lastContentAdded, "library.browse.sort.lastContentAdded", .descending))
        }
        values.append(jellyfinSortOption(.datePlayed, "library.browse.sort.datePlayed", .descending))
        if library.type == .movie {
            values.append(jellyfinSortOption(.playCount, "library.browse.sort.playCount", .descending))
        }
        return values
    }

    var jellyfinActiveFilterCount: Int {
        guard let query = browseSession?.query else { return 0 }
        return (query.watchStatus == .all ? 0 : 1)
            + (query.isResumable ? 1 : 0)
            + (query.isFavorite ? 1 : 0)
            + (query.genreIDs.isEmpty ? 0 : 1)
            + (query.years.isEmpty ? 0 : 1)
    }

    var browseSessionSort: LibraryBrowseSort? {
        browseSession?.query.sort
    }

    var jellyfinSortDirectionImage: String {
        browseSession?.query.sortDirection == .descending ? "arrow.down" : "arrow.up"
    }

    func togglePanel(_ panel: Panel) {
        if activePanel == panel {
            activePanel = nil
        } else {
            activePanel = panel
        }
    }

    func selectDisplayType(_ type: DisplayType) {
        guard type.key != selectedDisplayType?.key else { return }
        selectedDisplayType = type
        normalizeSelections(for: type)
        onDisplayTypeChanged?()
    }

    func toggleSort(_ sort: PlexSectionItemSort) {
        if let selection = selectedSort, selection.sort.key == sort.key {
            if selection.direction == sort.defaultDirection {
                selectedSort = SortSelection(sort: sort, direction: selection.direction.opposite)
            } else {
                selectedSort = nil
            }
        } else {
            selectedSort = SortSelection(sort: sort, direction: sort.defaultDirection)
        }
        onSelectionChanged?()
    }

    func toggleJellyfinSort(_ sort: JellyfinSortOption) {
        guard let browseSession else { return }
        if browseSession.query.sort == sort.id {
            browseSession.query.sortDirection = browseSession.query.sortDirection.opposite
        } else {
            browseSession.query.sort = sort.id
            browseSession.query.sortDirection = sort.defaultDirection
        }
        onSelectionChanged?()
    }

    func toggleFilter(_ filter: PlexSectionItemFilter) {
        if filter.isBoolean {
            if let existing = selectedFilters[filter.filter], existing.isEnabled {
                selectedFilters[filter.filter] = nil
            } else {
                selectedFilters[filter.filter] = FilterSelection(
                    filter: filter,
                    isEnabled: true,
                    selectedOption: nil,
                )
            }
            onSelectionChanged?()
        } else {
            activeFilterSheet = FilterSheetState(filter: filter)
            Task { await loadFilterOptionsIfNeeded(for: filter) }
        }
    }

    func toggleJellyfinFilter(_ filter: JellyfinFilter) {
        guard let browseSession else { return }
        switch filter {
        case .inProgress:
            browseSession.query.isResumable.toggle()
            if browseSession.query.isResumable {
                browseSession.query.watchStatus = .all
            }
            onSelectionChanged?()
        case .favorites:
            browseSession.query.isFavorite.toggle()
            onSelectionChanged?()
        case .watchStatus, .genres, .years:
            activeJellyfinFilterSheet = filter
            if filter == .genres || filter == .years {
                Task { await loadJellyfinFilterOptionsIfNeeded() }
            }
        }
    }

    func jellyfinFilterIsSelected(_ filter: JellyfinFilter) -> Bool {
        guard let query = browseSession?.query else { return false }
        return switch filter {
        case .watchStatus:
            query.watchStatus != .all
        case .inProgress:
            query.isResumable
        case .favorites:
            query.isFavorite
        case .genres:
            !query.genreIDs.isEmpty
        case .years:
            !query.years.isEmpty
        }
    }

    func jellyfinFilterLabel(_ filter: JellyfinFilter) -> String {
        guard let query = browseSession?.query else { return filter.title }
        switch filter {
        case .watchStatus:
            let value: String? = switch query.watchStatus {
            case .all: nil
            case .unplayed: String(localized: "library.browse.filters.unplayed")
            case .played: String(localized: "library.browse.filters.played")
            }
            return value.map { filter.title + ": " + $0 } ?? filter.title
        case .genres:
            return selectionCountLabel(filter.title, count: query.genreIDs.count)
        case .years:
            return selectionCountLabel(filter.title, count: query.years.count)
        case .inProgress, .favorites:
            return filter.title
        }
    }

    func jellyfinOptions(for filter: JellyfinFilter) -> [LibraryBrowseValueOption] {
        switch filter {
        case .watchStatus:
            [
                LibraryBrowseValueOption(
                    id: LibraryBrowseWatchStatus.all.rawValue,
                    title: String(localized: "library.browse.filters.all"),
                ),
                LibraryBrowseValueOption(
                    id: LibraryBrowseWatchStatus.unplayed.rawValue,
                    title: String(localized: "library.browse.filters.unplayed"),
                ),
                LibraryBrowseValueOption(
                    id: LibraryBrowseWatchStatus.played.rawValue,
                    title: String(localized: "library.browse.filters.played"),
                ),
            ]
        case .genres:
            jellyfinFilterOptions.genres
        case .years:
            jellyfinFilterOptions.years
        case .inProgress, .favorites:
            []
        }
    }

    func jellyfinOptionIsSelected(_ option: LibraryBrowseValueOption, for filter: JellyfinFilter) -> Bool {
        guard let query = browseSession?.query else { return false }
        return switch filter {
        case .watchStatus:
            query.watchStatus.rawValue == option.id
        case .genres:
            query.genreIDs.contains(option.id)
        case .years:
            Int(option.id).map(query.years.contains) ?? false
        case .inProgress, .favorites:
            false
        }
    }

    func selectJellyfinOption(_ option: LibraryBrowseValueOption, for filter: JellyfinFilter) {
        guard let browseSession else { return }
        switch filter {
        case .watchStatus:
            guard let status = LibraryBrowseWatchStatus(rawValue: option.id) else { return }
            browseSession.query.watchStatus = status
            if status != .all {
                browseSession.query.isResumable = false
            }
        case .genres:
            if browseSession.query.genreIDs.contains(option.id) {
                browseSession.query.genreIDs.remove(option.id)
            } else {
                browseSession.query.genreIDs.insert(option.id)
            }
        case .years:
            guard let year = Int(option.id) else { return }
            if browseSession.query.years.contains(year) {
                browseSession.query.years.remove(year)
            } else {
                browseSession.query.years.insert(year)
            }
        case .inProgress, .favorites:
            return
        }
        onSelectionChanged?()
    }

    func clearJellyfinFilter(_ filter: JellyfinFilter) {
        guard let browseSession else { return }
        switch filter {
        case .watchStatus:
            browseSession.query.watchStatus = .all
        case .inProgress:
            browseSession.query.isResumable = false
        case .favorites:
            browseSession.query.isFavorite = false
        case .genres:
            browseSession.query.genreIDs = []
        case .years:
            browseSession.query.years = []
        }
        onSelectionChanged?()
    }

    func selectFilterOption(_ option: FilterOption, for filter: PlexSectionItemFilter) {
        selectedFilters[filter.filter] = FilterSelection(filter: filter, isEnabled: true, selectedOption: option)
        onSelectionChanged?()
    }

    func clearFilter(_ filter: PlexSectionItemFilter) {
        selectedFilters[filter.filter] = nil
        onSelectionChanged?()
    }

    func filterSelection(for filter: PlexSectionItemFilter) -> FilterSelection? {
        selectedFilters[filter.filter]
    }

    func options(for filter: PlexSectionItemFilter) -> [FilterOption] {
        filterOptions[filter.filter] ?? []
    }

    func isLoadingOptions(for filter: PlexSectionItemFilter) -> Bool {
        filterOptionsLoading.contains(filter.filter)
    }

    func optionsError(for filter: PlexSectionItemFilter) -> String? {
        filterOptionsError[filter.filter]
    }

    func applyMeta(_ meta: PlexSectionItemMeta) {
        let types = meta.type.map(DisplayType.init)
        displayTypes = types

        if let selected = selectedDisplayType,
           let matching = types.first(where: { $0.key == selected.key })
        {
            selectedDisplayType = matching
        } else {
            selectedDisplayType = types.first(where: { $0.isActive }) ?? types.first
        }

        normalizeSelections(for: selectedDisplayType)
    }

    func buildQueryItems(
        baseItems: [URLQueryItem],
        includeCollections: Bool?,
        includeMeta: Bool,
    ) -> [URLQueryItem] {
        var items = baseItems

        setQueryItem(name: "includeCollections", value: includeCollections == true ? "1" : nil, in: &items)
        setQueryItem(name: "includeMeta", value: includeMeta ? "1" : nil, in: &items)

        if let selectedSort {
            let sortValue = selectedSort.direction == .asc
                ? selectedSort.sort.key
                : selectedSort.sort.descKey
            setQueryItem(name: "sort", value: sortValue, in: &items)
        } else {
            setQueryItem(name: "sort", value: nil, in: &items)
        }

        for selection in selectedFilters.values {
            if selection.filter.isBoolean {
                guard selection.isEnabled else { continue }
                setQueryItem(name: selection.filter.filter, value: "1", in: &items)
            } else if let option = selection.selectedOption {
                if let fastKey = option.fastKey,
                   let fastQueryItems = PlexEndpoint(key: fastKey)?.queryItems
                {
                    for fastItem in fastQueryItems {
                        setQueryItem(name: fastItem.name, value: fastItem.value, in: &items)
                    }
                } else {
                    setQueryItem(name: selection.filter.filter, value: option.key, in: &items)
                }
            }
        }

        return items
    }

    private func normalizeSelections(for displayType: DisplayType?) {
        guard let displayType else { return }
        let availableFilterKeys = Set(displayType.filters.map(\.filter))
        var updatedFilters: [String: FilterSelection] = [:]

        for filter in displayType.filters {
            if let existing = selectedFilters[filter.filter] {
                updatedFilters[filter.filter] = FilterSelection(
                    filter: filter,
                    isEnabled: existing.isEnabled,
                    selectedOption: existing.selectedOption,
                )
            }
        }

        selectedFilters = updatedFilters.filter { availableFilterKeys.contains($0.key) }

        if let selectedSort,
           !displayType.sorts.contains(where: { $0.key == selectedSort.sort.key })
        {
            self.selectedSort = nil
        }

        if selectedSort == nil,
           let activeSort = displayType.sorts.first(where: { $0.active == true })
        {
            selectedSort = SortSelection(sort: activeSort, direction: activeSort.defaultDirection)
        }
    }

    private func activeFilterSummaries() -> [String] {
        var summaries: [String] = []
        for selection in selectedFilters.values {
            if selection.filter.isBoolean {
                if selection.isEnabled {
                    summaries.append(selection.filter.title)
                }
            } else if let option = selection.selectedOption {
                summaries.append(selection.filter.title + ": " + option.title)
            }
        }
        return summaries.sorted()
    }

    private func sortDirectionLabel(for direction: PlexSortDirection) -> String {
        switch direction {
        case .asc:
            String(localized: "library.browse.sort.direction.asc")
        case .desc:
            String(localized: "library.browse.sort.direction.desc")
        }
    }

    private func jellyfinSortOption(
        _ id: LibraryBrowseSort,
        _ localizationKey: String.LocalizationValue,
        _ direction: LibraryBrowseSortDirection,
    ) -> JellyfinSortOption {
        JellyfinSortOption(id: id, title: String(localized: localizationKey), defaultDirection: direction)
    }

    private func jellyfinSortDirectionLabel(_ direction: LibraryBrowseSortDirection) -> String {
        switch direction {
        case .ascending:
            String(localized: "library.browse.sort.direction.asc")
        case .descending:
            String(localized: "library.browse.sort.direction.desc")
        }
    }

    private func selectionCountLabel(_ title: String, count: Int) -> String {
        count == 0 ? title : title + " · " + String(count)
    }

    private func loadJellyfinFilterOptionsIfNeeded() async {
        guard jellyfinFilterOptions.genres.isEmpty, jellyfinFilterOptions.years.isEmpty else { return }
        guard !isLoadingJellyfinFilterOptions, let browseService, let library else { return }
        isLoadingJellyfinFilterOptions = true
        jellyfinFilterOptionsError = nil
        defer { isLoadingJellyfinFilterOptions = false }
        do {
            jellyfinFilterOptions = try await browseService.browseFilterOptions(in: library)
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            jellyfinFilterOptionsError = error.localizedDescription
        }
    }

    private func loadFilterOptionsIfNeeded(for filter: PlexSectionItemFilter) async {
        let filterKey = filter.filter
        guard !filterOptionsLoading.contains(filterKey) else { return }
        guard filterOptions[filterKey] == nil else { return }
        guard let advancedService else { return }
        guard let endpoint = PlexEndpoint(key: filter.key) else { return }

        filterOptionsLoading.insert(filterKey)
        filterOptionsError[filterKey] = nil
        defer { filterOptionsLoading.remove(filterKey) }

        do {
            let values = try await advancedService.filterOptions(
                path: endpoint.path,
                queryItems: endpoint.queryItems,
            )
            let options = values.map(FilterOption.init)
            filterOptions[filterKey] = options
        } catch {
            filterOptionsError[filterKey] = error.localizedDescription
        }
    }

    private func setQueryItem(name: String, value: String?, in items: inout [URLQueryItem]) {
        items.removeAll { $0.name == name }
        if let value {
            items.append(URLQueryItem(name: name, value: value))
        }
    }
}
