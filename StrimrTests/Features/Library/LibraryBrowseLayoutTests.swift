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

    @Test(arguments: [MediaKind.movie, .clip])
    func `explicit default layout applies to every library kind`(kind: MediaKind) {
        let preferences = LibraryBrowsePreferences()

        #expect(preferences.resolvedLayout(for: kind, defaultLayout: .grid) == .grid)
        #expect(preferences.resolvedLayout(for: kind, defaultLayout: .list) == .list)
    }

    @Test func `saved layout wins over the default`() {
        let preferences = LibraryBrowsePreferences(layout: .grid)

        #expect(preferences.resolvedLayout(for: .clip, defaultLayout: .automatic) == .grid)
        #expect(preferences.resolvedLayout(for: .movie, defaultLayout: .list) == .grid)
        #expect(LibraryBrowsePreferences().resolvedLayout(for: .clip, defaultLayout: .automatic) == .list)
    }

    @Test func `picking the default layout clears the override`() {
        var preferences = LibraryBrowsePreferences(layout: .list)

        preferences.setLayout(.grid, for: .movie, defaultLayout: .automatic)
        #expect(preferences.layout == nil)

        preferences.setLayout(.list, for: .movie, defaultLayout: .automatic)
        #expect(preferences.layout == .list)

        preferences.setLayout(.list, for: .clip, defaultLayout: .automatic)
        #expect(preferences.layout == nil)
    }
}
