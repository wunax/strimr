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
        let type: PlexItemType
        let title: String
        let isActive: Bool
        let filters: [PlexSectionItemFilter]
        let sorts: [PlexSectionItemSort]

        init(metaType: PlexSectionItemMetaType) {
            id = metaType.key
            key = metaType.key
            type = metaType.type
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

    var displayTypes: [DisplayType] = []
    var selectedDisplayType: DisplayType?
    var activePanel: Panel?
    var selectedSort: SortSelection?
    var selectedFilters: [String: FilterSelection] = [:]
    var activeFilterSheet: FilterSheetState?
    var filterOptions: [String: [FilterOption]] = [:]
    var filterOptionsLoading: Set<String> = []
    var filterOptionsError: [String: String] = [:]

    @ObservationIgnored var onSelectionChanged: (() -> Void)?
    @ObservationIgnored var onDisplayTypeChanged: (() -> Void)?
    @ObservationIgnored private let context: PlexAPIContext

    init(context: PlexAPIContext) {
        self.context = context
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
        !availableFilters.isEmpty
    }

    var showsSortPill: Bool {
        !availableSorts.isEmpty
    }

    var typePillTitle: String {
        selectedDisplayType?.title ?? String(localized: "library.browse.type.title")
    }

    var filterPillTitle: String {
        let base = String(localized: "library.browse.filters.title")
        let summaries = activeFilterSummaries()
        guard !summaries.isEmpty else { return base }
        if summaries.count <= 2 {
            return base + " · " + summaries.joined(separator: ", ")
        }
        return String(localized: "library.browse.filters.count \(summaries.count)")
    }

    var sortPillTitle: String {
        let base = String(localized: "library.browse.sort.title")
        guard let selectedSort else { return base }
        let directionLabel = sortDirectionLabel(for: selectedSort.direction)
        return base + " · " + selectedSort.sort.title + " · " + directionLabel
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

    private func loadFilterOptionsIfNeeded(for filter: PlexSectionItemFilter) async {
        let filterKey = filter.filter
        guard !filterOptionsLoading.contains(filterKey) else { return }
        guard filterOptions[filterKey] == nil else { return }
        guard let sectionRepository = try? SectionRepository(context: context) else { return }
        guard let endpoint = PlexEndpoint(key: filter.key) else { return }

        filterOptionsLoading.insert(filterKey)
        filterOptionsError[filterKey] = nil
        defer { filterOptionsLoading.remove(filterKey) }

        do {
            let response = try await sectionRepository.getFilterOptions(
                path: endpoint.path,
                queryItems: endpoint.queryItems,
            )
            let options = (response.mediaContainer.directory ?? [])
                .map(FilterOption.init)
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
