@testable import Strimr
import Testing

struct LibraryBrowseLayoutTests {
    @Test func `home video libraries open as a list`() {
        #expect(LibraryBrowseLayout.default(for: .clip) == .list)
    }

    @Test(arguments: [MediaKind.movie, .series, .collection, .playlist])
    func `other libraries open as a grid`(kind: MediaKind) {
        #expect(LibraryBrowseLayout.default(for: kind) == .grid)
    }

    @Test func `saved layout wins over the default`() {
        let preferences = LibraryBrowsePreferences(layout: .grid)

        #expect(preferences.resolvedLayout(for: .clip) == .grid)
        #expect(LibraryBrowsePreferences().resolvedLayout(for: .clip) == .list)
    }
}
