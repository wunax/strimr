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

struct LibraryBrowsePreferences: Codable, Equatable {
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
