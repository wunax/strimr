import Foundation

struct PlexAdvancedBrowsePage {
    let items: [LibraryBrowseItem]
    let totalCount: Int
    let meta: PlexSectionItemMeta?
}

struct PlexAdvancedSectionCharacter {
    let title: String
    let size: Int
}

@MainActor
protocol PlexAdvancedLibraryService: AnyObject {
    func advancedBrowse(
        path: String,
        queryItems: [URLQueryItem],
        startIndex: Int,
        limit: Int
    ) async throws -> PlexAdvancedBrowsePage

    func filterOptions(path: String, queryItems: [URLQueryItem]) async throws -> [PlexFilterDirectory]
    func sectionCharacters(path: String, queryItems: [URLQueryItem]) async throws -> [PlexAdvancedSectionCharacter]
    func collectionCharacters(sectionID: Int) async throws -> [PlexAdvancedSectionCharacter]
    func collectionPage(sectionID: Int, startIndex: Int, limit: Int) async throws -> MediaPage<MediaDisplayItem>
}
