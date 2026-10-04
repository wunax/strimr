import Foundation
@testable import Strimr
import Testing

@MainActor
struct LibraryBrowseControlsViewModelTests {
    private typealias PlexSelection = LibraryBrowsePreferences.PlexSelection

    private let movieTypeKey = "/library/sections/1/all?type=1"

    @Test func `pending selection builds sort and filters before meta`() {
        let controls = makeControls(restoring: PlexSelection(
            displayTypeKey: movieTypeKey,
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: [
                "unwatched": .init(isEnabled: true),
                "genre": .init(
                    isEnabled: true,
                    optionKey: "28",
                    optionFastKey: "/library/sections/1/all?genre=28",
                    optionTitle: "Action",
                ),
            ],
        ))

        let items = queryItems(controls)

        #expect(controls.requestedDisplayTypeKey == movieTypeKey)
        #expect(items["sort"] == "addedAt:desc")
        #expect(items["unwatched"] == "1")
        #expect(items["genre"] == "28")
        #expect(items["includeMeta"] == "1")
    }

    @Test func `pending filter without fast key uses the option key`() {
        let controls = makeControls(restoring: PlexSelection(
            filters: ["genre": .init(isEnabled: true, optionKey: "12", optionTitle: "Drama")],
        ))

        let items = queryItems(controls)

        #expect(items["genre"] == "12")
        #expect(items["sort"] == nil)
    }

    @Test func `valid pending selection is applied without refresh`() throws {
        let controls = makeControls(restoring: PlexSelection(
            displayTypeKey: movieTypeKey,
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: ["genre": .init(isEnabled: true, optionKey: "28", optionTitle: "Action")],
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(!restoreChanged)
        #expect(controls.selectedDisplayType?.key == movieTypeKey)
        #expect(controls.selectedSort?.sort.key == "addedAt")
        #expect(controls.selectedSort?.direction == .desc)
        #expect(controls.filterPillTitle.hasSuffix("Genre: Action"))
        #expect(queryItems(controls, includeMeta: false)["sort"] == "addedAt:desc")
    }

    @Test func `unknown sort falls back to the server default`() throws {
        let controls = makeControls(restoring: PlexSelection(
            sortKey: "removed",
            sortDirection: .asc,
            sortQueryValue: "removed",
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(controls.selectedSort?.direction == .asc)
        #expect(controls.plexSelection.sortQueryValue == "titleSort")
    }

    @Test func `unknown filter is dropped`() throws {
        let controls = makeControls(restoring: PlexSelection(
            filters: [
                "unwatched": .init(isEnabled: true),
                "removed": .init(isEnabled: true, optionKey: "1"),
            ],
        ))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(Set(controls.selectedFilters.keys) == ["unwatched"])
        #expect(Set(controls.plexSelection.filters.keys) == ["unwatched"])
    }

    @Test func `unknown display type falls back to the active type`() throws {
        let controls = makeControls(restoring: PlexSelection(displayTypeKey: "/library/sections/1/all?type=4"))

        let restoreChanged = try controls.applyMeta(meta())

        #expect(restoreChanged)
        #expect(controls.selectedDisplayType?.key == movieTypeKey)
        #expect(controls.plexSelection.displayTypeKey == movieTypeKey)
    }

    @Test func `meta without a pending selection does not ask for a refresh`() throws {
        let controls = makeControls(restoring: nil)

        let restoreChanged = try controls.applyMeta(meta())

        #expect(!restoreChanged)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(!controls.canResetSelection)
    }

    @Test func `reset restores the server default sort and clears filters`() throws {
        let controls = makeControls(restoring: PlexSelection(
            sortKey: "addedAt",
            sortDirection: .desc,
            sortQueryValue: "addedAt:desc",
            filters: ["unwatched": .init(isEnabled: true)],
        ))
        try controls.applyMeta(meta())
        var didReset = false
        controls.onSelectionReset = { didReset = true }

        #expect(controls.canResetSelection)
        controls.resetSelection()

        #expect(didReset)
        #expect(controls.selectedFilters.isEmpty)
        #expect(controls.selectedSort?.sort.key == "titleSort")
        #expect(!controls.canResetSelection)
    }

    private func makeControls(restoring selection: PlexSelection?) -> LibraryBrowseControlsViewModel {
        LibraryBrowseControlsViewModel(advancedService: nil, pendingRestore: selection)
    }

    private func meta() throws -> PlexSectionItemMeta {
        try Fixtures.decode(PlexSectionItemMeta.self, from: "plex-section-meta")
    }

    private func queryItems(_ controls: LibraryBrowseControlsViewModel, includeMeta: Bool = true) -> [String: String] {
        let items = controls.buildQueryItems(baseItems: [], includeCollections: nil, includeMeta: includeMeta)
        return Dictionary(items.map { ($0.name, $0.value ?? "") }, uniquingKeysWith: { _, last in last })
    }
}
