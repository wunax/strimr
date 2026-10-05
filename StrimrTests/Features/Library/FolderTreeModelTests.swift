import Foundation
@testable import Strimr
import Testing

@MainActor
struct FolderTreeModelTests {
    private let rootKey = "/library/sections/1/folder"
    private let moviesKey = "/library/sections/1/folder?parent=10"
    private let sagaKey = "/library/sections/1/folder?parent=11"

    @Test func `expanding a folder inserts its children below it`() async {
        let model = makeModel(listings: [
            rootKey: [folder(moviesKey, "Movies"), folder("/library/sections/1/folder?parent=12", "Shows")],
            moviesKey: [folder(sagaKey, "Saga")],
        ])
        await model.loadRoot()

        await model.toggle(LibraryBrowseFolderItem(id: moviesKey, key: moviesKey, title: "Movies"))

        #expect(model.rows.map(\.depth) == [0, 1, 0])
        #expect(model.rows.map(\.isExpanded) == [true, false, false])
    }

    @Test func `collapsing keeps children cached`() async throws {
        let loader = RecordingLoader(listings: [rootKey: [folder(moviesKey, "Movies")], moviesKey: []])
        let model = try FolderTreeModel(rootEndpoint: #require(PlexEndpoint(key: rootKey)), loadPage: loader.load)
        await model.loadRoot()
        let movies = LibraryBrowseFolderItem(id: moviesKey, key: moviesKey, title: "Movies")

        await model.toggle(movies)
        await model.toggle(movies)
        await model.toggle(movies)

        #expect(loader.requestedPaths.count == 2)
        #expect(model.rows.first?.isExpanded == true)
    }

    @Test func `listings are loaded across pages`() async throws {
        let items = (0 ..< 5).map { folder("/library/sections/1/folder?parent=\($0)", "Folder \($0)") }
        let model = try FolderTreeModel(
            rootEndpoint: #require(PlexEndpoint(key: rootKey)),
            pageSize: 2,
            loadPage: RecordingLoader(listings: [rootKey: items]).load,
        )

        await model.loadRoot()

        #expect(model.rootItems == items)
    }

    @Test func `a failed expansion collapses the folder`() async {
        let model = makeModel(listings: [rootKey: [folder(moviesKey, "Movies")]])
        await model.loadRoot()

        await model.toggle(LibraryBrowseFolderItem(id: moviesKey, key: moviesKey, title: "Movies"))

        #expect(model.rows.map(\.isExpanded) == [false])
    }

    private func makeModel(listings: [String: [LibraryBrowseItem]]) -> FolderTreeModel {
        FolderTreeModel(rootEndpoint: PlexEndpoint(key: rootKey)!, loadPage: RecordingLoader(listings: listings).load)
    }

    private func folder(_ key: String, _ title: String) -> LibraryBrowseItem {
        .folder(LibraryBrowseFolderItem(id: key, key: key, title: title))
    }
}

@MainActor
private final class RecordingLoader {
    struct MissingListing: Error {}

    let listings: [String: [LibraryBrowseItem]]
    private(set) var requestedPaths: [String] = []

    init(listings: [String: [LibraryBrowseItem]]) {
        self.listings = listings
    }

    func load(endpoint: PlexEndpoint, startIndex: Int, limit: Int) async throws -> PlexAdvancedBrowsePage {
        let key = endpoint.queryItems.isEmpty
            ? endpoint.path
            : "\(endpoint.path)?\(endpoint.queryItems.map { "\($0.name)=\($0.value ?? "")" }.joined(separator: "&"))"
        requestedPaths.append(key)
        guard let items = listings[key] else { throw MissingListing() }
        let page = Array(items.dropFirst(startIndex).prefix(limit))
        return PlexAdvancedBrowsePage(items: page, totalCount: items.count, meta: nil)
    }
}
