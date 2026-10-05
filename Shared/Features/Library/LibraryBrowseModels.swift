import Foundation
import Observation

enum LibraryBrowseSortDirection: String, Codable, Equatable, Sendable {
    case ascending
    case descending

    var opposite: Self {
        self == .ascending ? .descending : .ascending
    }
}

enum LibraryBrowseSort: String, Codable, Equatable, Sendable {
    case name
    case releaseDate
    case dateAdded
    case rating
    case datePlayed
    case playCount
    case lastContentAdded
}

enum LibraryBrowseWatchStatus: String, Codable, Equatable, Sendable {
    case all
    case unplayed
    case played
}

struct LibraryBrowseQuery: Codable, Equatable, Sendable {
    var sort: LibraryBrowseSort = .name
    var sortDirection: LibraryBrowseSortDirection = .ascending
    var watchStatus: LibraryBrowseWatchStatus = .all
    var isResumable = false
    var isFavorite = false
    var genreIDs: Set<String> = []
    var years: Set<Int> = []
}

struct LibraryBrowseValueOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

struct LibraryBrowseFilterOptions: Equatable, Sendable {
    var genres: [LibraryBrowseValueOption] = []
    var years: [LibraryBrowseValueOption] = []
}

@MainActor
@Observable
final class LibraryBrowseSession {
    var query = LibraryBrowseQuery()
    @ObservationIgnored var externalQueryChangeHandler: (() -> Void)?
    @ObservationIgnored private var hasRestoredQuery = false

    /// Applies the saved query once per session, so view models recreated by SwiftUI cannot clobber later changes.
    func restoreQueryIfNeeded(_ savedQuery: LibraryBrowseQuery?) {
        guard !hasRestoredQuery else { return }
        hasRestoredQuery = true
        if let savedQuery {
            query = savedQuery
        }
    }
}

enum LibraryBrowseLayout: String, Codable, Equatable, Sendable {
    case grid
    case list

    /// Home video libraries have extracted thumbnails and long titles, which read better as a list.
    static func `default`(for kind: MediaKind) -> Self {
        kind == .clip ? .list : .grid
    }
}

enum LibraryDefaultLayout: String, Codable, CaseIterable, Hashable {
    case automatic
    case grid
    case list

    var title: String {
        switch self {
        case .automatic:
            String(localized: "settings.interface.libraries.defaultLayout.automatic")
        case .grid:
            String(localized: "library.browse.layout.grid")
        case .list:
            String(localized: "library.browse.layout.list")
        }
    }

    func layout(for kind: MediaKind) -> LibraryBrowseLayout {
        switch self {
        case .automatic:
            .default(for: kind)
        case .grid:
            .grid
        case .list:
            .list
        }
    }
}

struct LibraryBrowsePreferences: Codable, Equatable {
    var layout: LibraryBrowseLayout?
    /// Shows Plex folder listings as an expandable tree instead of one folder level at a time.
    var showsFolderTree: Bool?
    var plex: PlexSelection?
    var jellyfinQuery: LibraryBrowseQuery?

    struct PlexSelection: Codable, Equatable {
        var displayTypeKey: String?
        var sortKey: String?
        var sortDirection: PlexSortDirection?
        /// `key` or `descKey`, kept raw because `descKey` is only known once `meta` is loaded.
        var sortQueryValue: String?
        /// Keyed by `PlexSectionItemFilter.filter`.
        var filters: [String: PlexFilter] = [:]

        struct PlexFilter: Codable, Equatable {
            var isEnabled: Bool
            var optionKey: String?
            var optionFastKey: String?
            var optionTitle: String?
        }
    }

    func resolvedLayout(for kind: MediaKind, defaultLayout: LibraryDefaultLayout) -> LibraryBrowseLayout {
        layout ?? defaultLayout.layout(for: kind)
    }

    /// Only a layout that differs from the default is saved, so changing the default reaches every other library.
    mutating func setLayout(_ layout: LibraryBrowseLayout, for kind: MediaKind, defaultLayout: LibraryDefaultLayout) {
        self.layout = layout == defaultLayout.layout(for: kind) ? nil : layout
    }

    /// Plex section keys repeat across servers, so the key is scoped by provider, server and account.
    static func key(scopeID: String, libraryID: String) -> String {
        "\(scopeID)|\(libraryID)"
    }
}

@MainActor
protocol AdvancedLibraryBrowseService: AnyObject {
    func browseItems(
        in library: Library,
        parentID: String?,
        query: LibraryBrowseQuery,
        startIndex: Int,
        limit: Int,
    ) async throws -> MediaPage<MediaDisplayItem>

    func browseFilterOptions(in library: Library) async throws -> LibraryBrowseFilterOptions
}

struct LibraryBrowseFolderItem: Identifiable, Equatable {
    let id: String
    let key: String
    let title: String
}

enum LibraryBrowseItem: Identifiable, Equatable {
    case media(MediaDisplayItem)
    case folder(LibraryBrowseFolderItem)

    var id: String {
        switch self {
        case let .media(item):
            item.id
        case let .folder(item):
            item.id
        }
    }
}
