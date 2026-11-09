import Foundation

/// Tracks which fixed-size pages of a listing are loaded or in flight, so any position can be loaded on its own.
nonisolated struct LibraryBrowsePageTracker {
    let pageSize: Int
    private(set) var loadedStarts: Set<Int> = []
    private(set) var loadingStarts: Set<Int> = []

    func pageStart(for index: Int) -> Int {
        max(0, index / pageSize) * pageSize
    }

    /// The page holding `index` and two on each side, minus those already loaded or in flight. `totalCount` of
    /// `nil` means the size is not known yet, so no page is left out at the end.
    mutating func pagesToLoad(around index: Int, totalCount: Int?, isIndexLoaded: Bool) -> [Int] {
        guard index >= 0 else { return [] }
        let start = pageStart(for: index)
        // A page counted as loaded can still miss this item after a deletion shifted the listing.
        if !isIndexLoaded, !loadingStarts.contains(start) {
            loadedStarts.remove(start)
        }
        return (-2 ... 2)
            .map { start + $0 * pageSize }
            .filter { pageStart in
                pageStart >= 0 && pageStart < (totalCount ?? .max)
                    && !loadedStarts.contains(pageStart) && !loadingStarts.contains(pageStart)
            }
    }

    /// Returns false when the page is already loaded or in flight.
    mutating func begin(_ start: Int) -> Bool {
        guard !loadedStarts.contains(start), !loadingStarts.contains(start) else { return false }
        loadingStarts.insert(start)
        return true
    }

    mutating func finish(_ start: Int, loaded: Bool) {
        loadingStarts.remove(start)
        if loaded {
            loadedStarts.insert(start)
        }
    }

    mutating func invalidateLoaded() {
        loadedStarts.removeAll()
    }

    mutating func reset() {
        loadedStarts.removeAll()
        loadingStarts.removeAll()
    }

    /// For servers that do not report the listing size: the loaded items plus one more page while pages come back
    /// full, so the next page has room to appear and load.
    static func estimatedTotal(current: Int, start: Int, received: Int, pageSize: Int) -> Int {
        let loadedEnd = start + received
        if received < pageSize {
            return loadedEnd
        }
        return max(current, loadedEnd + pageSize)
    }
}
