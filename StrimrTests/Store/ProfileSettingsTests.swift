import Foundation
@testable import Strimr
import Testing

@MainActor
struct ProfileSettingsTests {
    private let defaults = TestDefaults.make()
    private let serverA = ServerIdentity(provider: .plex, id: "server-a")
    private let serverB = ServerIdentity(provider: .jellyfin, id: "server-b")

    @Test func `library settings of an unreachable or disabled server are kept`() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateLibraryPreferences(profileID: "p") {
            $0.setHidden(LibraryIdentity(server: serverA, libraryID: "1"), hidden: true)
            $0.setOrder([
                LibraryIdentity(server: serverB, libraryID: "x"),
                LibraryIdentity(server: serverA, libraryID: "2"),
            ])
        }
        let before = settings.libraryPreferences(profileID: "p")

        // Only server B answered: server A's libraries are absent from the list but keep their settings.
        let visible = before.ordered([
            Library(id: "x", title: "X", type: .movie, server: serverB),
            Library(id: "y", title: "Y", type: .movie, server: serverB),
        ])

        #expect(visible.map(\.id) == ["x", "y"])
        #expect(settings.libraryPreferences(profileID: "p") == before)
    }

    @Test func `library order keeps the slots of absent libraries`() {
        var preferences = LibraryPreferences()
        let a1 = LibraryIdentity(server: serverA, libraryID: "1")
        let a2 = LibraryIdentity(server: serverA, libraryID: "2")
        let b1 = LibraryIdentity(server: serverB, libraryID: "1")
        preferences.setOrder([a1, b1, a2])

        // Server B is unreachable: reordering A's libraries leaves B's slot in place.
        preferences.setOrder([a2, a1])

        #expect(preferences.libraryOrder == [a2, b1, a1])
    }

    @Test func `new libraries go after the ordered ones`() {
        var preferences = LibraryPreferences()
        preferences.setOrder([LibraryIdentity(server: serverB, libraryID: "1")])
        let libraries = [
            Library(id: "1", title: "A1", type: .movie, server: serverA),
            Library(id: "1", title: "B1", type: .movie, server: serverB),
        ]

        #expect(preferences.ordered(libraries).map(\.title) == ["B1", "A1"])
    }

    @Test func `removing an account removes its libraries and rows for every profile`() {
        let settings = SettingsManager(userDefaults: defaults)
        for profileID in ["p1", "p2"] {
            settings.updateLibraryPreferences(profileID: profileID) {
                $0.setHidden(LibraryIdentity(server: serverA, libraryID: "1"), hidden: true)
                $0.setHidden(LibraryIdentity(server: serverB, libraryID: "1"), hidden: true)
                $0.navigationLibraries = [LibraryIdentity(server: serverA, libraryID: "2")]
            }
            settings.setHomeRowOrder(
                [HomeRow.continueWatchingID, "home:plex:server-a:hub:recent::/x", "home:jellyfin:server-b:hub:y::/y"],
                profileID: profileID,
            )
            settings.setHomeRowVisibility("home:plex:server-a:hub:recent::/x", visible: false, profileID: profileID)
        }

        settings.removeSettings(of: [serverA])

        for profileID in ["p1", "p2"] {
            let libraries = settings.libraryPreferences(profileID: profileID)
            #expect(libraries.hiddenLibraries == [LibraryIdentity(server: serverB, libraryID: "1")])
            #expect(libraries.navigationLibraries.isEmpty)
            let rows = settings.homeRowPreferences(profileID: profileID)
            #expect(rows.orderedRowIDs == [HomeRow.continueWatchingID, "home:jellyfin:server-b:hub:y::/y"])
            #expect(rows.hiddenRowIDs.isEmpty)
        }
    }

    @Test func `deleted libraries are pruned after a successful load only for their server`() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateLibraryPreferences(profileID: "p") {
            $0.hiddenLibraries = [
                LibraryIdentity(server: serverA, libraryID: "1"),
                LibraryIdentity(server: serverA, libraryID: "2"),
                LibraryIdentity(server: serverB, libraryID: "2"),
            ]
        }

        settings.pruneLibraries(of: serverA, keeping: ["1"])

        #expect(settings.libraryPreferences(profileID: "p").hiddenLibraries == [
            LibraryIdentity(server: serverA, libraryID: "1"),
            LibraryIdentity(server: serverB, libraryID: "2"),
        ])
    }

    @Test func `profile settings are independent and removable`() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.setHomeRowVisibility(HomeRow.nextUpID, visible: false, profileID: "p1")
        settings.updateLibraryPreferences(profileID: "p1") {
            $0.setHidden(LibraryIdentity(server: serverA, libraryID: "1"), hidden: true)
        }

        #expect(settings.homeRowPreferences(profileID: "p2").hiddenRowIDs.isEmpty)

        settings.removeSettings(profileID: "p1")

        #expect(settings.homeRowPreferences(profileID: "p1") == HomeRowPreferences())
        #expect(settings.libraryPreferences(profileID: "p1") == LibraryPreferences())
    }

    @Test func `per profile settings survive a reload`() {
        let settings = SettingsManager(userDefaults: defaults)
        settings.updateLibraryPreferences(profileID: "p") {
            $0.navigationLibraries = [LibraryIdentity(server: serverB, libraryID: "abc")]
        }

        let reloaded = SettingsManager(userDefaults: defaults)

        #expect(reloaded.libraryPreferences(profileID: "p").navigationLibraries == [
            LibraryIdentity(server: serverB, libraryID: "abc"),
        ])
    }
}
