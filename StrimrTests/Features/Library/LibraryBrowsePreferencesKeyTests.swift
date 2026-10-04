@testable import Strimr
import Testing

struct LibraryBrowsePreferencesKeyTests {
    @Test func `same Plex section on two servers gets two keys`() {
        let first = LibraryBrowsePreferences.key(scopeID: "plex|server-a|account", libraryID: "1")
        let second = LibraryBrowsePreferences.key(scopeID: "plex|server-b|account", libraryID: "1")

        #expect(first != second)
    }

    @Test func `same section for two accounts gets two keys`() {
        let first = LibraryBrowsePreferences.key(scopeID: "plex|server|account-a", libraryID: "1")
        let second = LibraryBrowsePreferences.key(scopeID: "plex|server|account-b", libraryID: "1")

        #expect(first != second)
    }
}
