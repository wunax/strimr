import Foundation
@testable import Strimr
import Testing

struct AppSettingsTests {
    @Test func `missing library browse preferences decode as empty`() throws {
        let settings = try decode(#"{"interface":{"displayPlaylists":false}}"#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `corrupt library browse preferences keep other settings`() throws {
        let settings = try decode(#"""
        {"interface":{"displayPlaylists":false,"libraryBrowseByKey":{"plex|server|account|1":{"plex":{"filters":42}}}}}
        """#)

        #expect(settings.interface.libraryBrowseByKey.isEmpty)
        #expect(!settings.interface.displayPlaylists)
    }

    @Test func `library browse preferences survive a round trip`() throws {
        var query = LibraryBrowseQuery()
        query.sort = .dateAdded
        query.sortDirection = .descending
        query.watchStatus = .unplayed
        query.isFavorite = true
        query.genreIDs = ["genre"]
        query.years = [1999, 2024]
        let preferences = LibraryBrowsePreferences(
            plex: .init(
                displayTypeKey: "/library/sections/1/all?type=1",
                sortKey: "addedAt",
                sortDirection: .desc,
                sortQueryValue: "addedAt:desc",
                filters: ["genre": .init(isEnabled: true, optionKey: "28", optionFastKey: nil, optionTitle: "Action")],
            ),
            jellyfinQuery: query,
        )
        var settings = AppSettings()
        settings.interface.libraryBrowseByKey["key"] = preferences

        let decoded = try JSONDecoder().decode(AppSettings.self, from: JSONEncoder().encode(settings))

        #expect(decoded.interface.libraryBrowseByKey["key"] == preferences)
    }

    @MainActor
    @Test func `saved library browse preferences survive a reload`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        var preferences = LibraryBrowsePreferences()
        preferences.plex = .init(sortKey: "addedAt", sortDirection: .desc, sortQueryValue: "addedAt:desc")

        SettingsManager(userDefaults: defaults).setLibraryBrowsePreferences(preferences, for: "key")
        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.libraryBrowsePreferences(for: "key") == preferences)
    }

    @Test func `missing library display defaults decode as automatic and medium`() throws {
        let settings = try decode(#"{"interface":{"libraryDefaultLayout":"mosaic"}}"#)

        #expect(settings.interface.libraryDefaultLayout == .automatic)
        #expect(settings.interface.posterSize == .medium)
    }

    @MainActor
    @Test func `resetting library layouts keeps sort and filters`() throws {
        let defaults = try #require(UserDefaults(suiteName: #function))
        defer { defaults.removePersistentDomain(forName: #function) }
        let manager = SettingsManager(userDefaults: defaults)
        var withSelection = LibraryBrowsePreferences(layout: .list)
        withSelection.plex = .init(sortKey: "addedAt")
        manager.setLibraryBrowsePreferences(withSelection, for: "a")
        manager.setLibraryBrowsePreferences(LibraryBrowsePreferences(layout: .grid), for: "b")
        #expect(manager.customLibraryLayoutCount == 2)

        manager.resetLibraryLayouts()

        #expect(manager.customLibraryLayoutCount == 0)
        #expect(manager.libraryBrowsePreferences(for: "a").plex?.sortKey == "addedAt")
        #expect(manager.interface.libraryBrowseByKey["b"] == nil)
    }

    private func decode(_ json: String) throws -> AppSettings {
        try JSONDecoder().decode(AppSettings.self, from: Data(json.utf8))
    }
}
