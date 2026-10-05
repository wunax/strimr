import Foundation
import Observation

/// Expandable view of a Plex folder listing: children load on first expansion and stay cached.
@MainActor
@Observable
final class FolderTreeModel {
    typealias PageLoader = @MainActor (PlexEndpoint, _ startIndex: Int, _ limit: Int) async throws
        -> PlexAdvancedBrowsePage

    struct Row: Identifiable, Equatable {
        let id: String
        let item: LibraryBrowseItem
        let depth: Int
        let isExpanded: Bool
        let isLoading: Bool
    }

    private(set) var rootItems: [LibraryBrowseItem] = []
    private(set) var isLoadingRoot = false
    private(set) var hasLoadedRoot = false
    private(set) var errorMessage: String?
    private var childrenByFolder: [String: [LibraryBrowseItem]] = [:]
    private var expandedFolders: Set<String> = []
    private var loadingFolders: Set<String> = []

    @ObservationIgnored private let rootEndpoint: PlexEndpoint
    @ObservationIgnored private let loadPage: PageLoader
    @ObservationIgnored private let pageSize: Int

    init(rootEndpoint: PlexEndpoint, pageSize: Int = 100, loadPage: @escaping PageLoader) {
        self.rootEndpoint = rootEndpoint
        self.pageSize = pageSize
        self.loadPage = loadPage
    }

    var rows: [Row] {
        var rows: [Row] = []
        appendRows(for: rootItems, depth: 0, parentPath: "", into: &rows)
        return rows
    }

    func loadRoot() async {
        isLoadingRoot = true
        errorMessage = nil
        defer { isLoadingRoot = false }
        do {
            rootItems = try await loadAll(from: rootEndpoint)
            hasLoadedRoot = true
        } catch {
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
            errorMessage = error.localizedDescription
        }
    }

    func toggle(_ folder: LibraryBrowseFolderItem) async {
        if expandedFolders.contains(folder.key) {
            expandedFolders.remove(folder.key)
            return
        }
        expandedFolders.insert(folder.key)
        guard childrenByFolder[folder.key] == nil, !loadingFolders.contains(folder.key) else { return }
        guard let endpoint = PlexEndpoint(key: folder.key) else {
            expandedFolders.remove(folder.key)
            return
        }

        loadingFolders.insert(folder.key)
        defer { loadingFolders.remove(folder.key) }
        do {
            childrenByFolder[folder.key] = try await loadAll(from: endpoint)
        } catch {
            expandedFolders.remove(folder.key)
            guard !error.isCancellation else { return }
            ErrorReporter.capture(error)
        }
    }

    private func loadAll(from endpoint: PlexEndpoint) async throws -> [LibraryBrowseItem] {
        var items: [LibraryBrowseItem] = []
        while true {
            let page = try await loadPage(endpoint, items.count, pageSize)
            items.append(contentsOf: page.items)
            if page.items.isEmpty || items.count >= page.totalCount {
                return items
            }
        }
    }

    /// Row ids include the parent path because the same media can appear under several folders.
    private func appendRows(
        for items: [LibraryBrowseItem],
        depth: Int,
        parentPath: String,
        into rows: inout [Row],
    ) {
        for item in items {
            let path = "\(parentPath)/\(item.id)"
            guard case let .folder(folder) = item else {
                rows.append(Row(id: path, item: item, depth: depth, isExpanded: false, isLoading: false))
                continue
            }
            let isExpanded = expandedFolders.contains(folder.key)
            rows.append(Row(
                id: path,
                item: item,
                depth: depth,
                isExpanded: isExpanded,
                isLoading: loadingFolders.contains(folder.key),
            ))
            if isExpanded, let children = childrenByFolder[folder.key] {
                appendRows(for: children, depth: depth + 1, parentPath: path, into: &rows)
            }
        }
    }
}
