import Foundation
import Observation

enum LibraryBrowseSortDirection: String, Equatable, Sendable {
    case ascending
    case descending

    var opposite: Self {
        self == .ascending ? .descending : .ascending
    }
}

enum LibraryBrowseSort: String, Equatable, Sendable {
    case name
    case releaseDate
    case dateAdded
    case rating
    case datePlayed
    case playCount
    case lastContentAdded
}

enum LibraryBrowseWatchStatus: String, Equatable, Sendable {
    case all
    case unplayed
    case played
}

struct LibraryBrowseQuery: Equatable, Sendable {
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

struct LibraryGenre: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
}

@MainActor
@Observable
final class LibraryBrowseSession {
    var query = LibraryBrowseQuery()
    @ObservationIgnored var externalQueryChangeHandler: (() -> Void)?

    func selectGenre(id: String) {
        query.genreIDs = [id]
        externalQueryChangeHandler?()
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
    func genres(in library: Library) async throws -> [LibraryGenre]
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
