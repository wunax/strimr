import Foundation
@testable import Strimr
import Testing

struct LibraryDetailTabTests {
    private let plexMovies = Library(
        id: "1",
        title: "Movies",
        type: .movie,
        sectionId: 1,
        server: ServerIdentity(provider: .plex, id: "server"),
    )

    @Test func `restores the saved tab when it is still available`() {
        let tab = LibraryDetailTab.resolved(
            saved: .collections,
            available: LibraryDetailTab.allCases,
            library: plexMovies,
        )

        #expect(tab == .collections)
    }

    @Test func `falls back to the default when the saved tab is hidden`() {
        let available = LibraryDetailTab.available(
            for: plexMovies,
            provider: .plex,
            displaysCollections: false,
            displaysPlaylists: true,
        )

        let tab = LibraryDetailTab.resolved(saved: .collections, available: available, library: plexMovies)

        #expect(tab == .recommended)
    }

    @Test func `opens browse by default in a shared library`() {
        let shared = Library(
            id: "shared",
            title: "Shared",
            type: .unknown,
            isShared: true,
            server: ServerIdentity(provider: .plex, id: "server"),
        )

        let tab = LibraryDetailTab.resolved(saved: nil, available: [.browse], library: shared)

        #expect(tab == .browse)
    }

    @Test func `does not save the default tab`() {
        var preferences = LibraryBrowsePreferences()

        preferences.setSelectedTab(.browse, for: plexMovies)
        #expect(preferences.selectedTab == .browse)

        preferences.setSelectedTab(.recommended, for: plexMovies)
        #expect(preferences.selectedTab == nil)
        #expect(preferences == LibraryBrowsePreferences())
    }

    @Test func `keeps other saved preferences when decoding a saved tab`() throws {
        var preferences = LibraryBrowsePreferences()
        preferences.layout = .list
        preferences.setSelectedTab(.playlists, for: plexMovies)

        let data = try JSONEncoder().encode(preferences)
        let decoded = try JSONDecoder().decode(LibraryBrowsePreferences.self, from: data)

        #expect(decoded == preferences)
    }
}
