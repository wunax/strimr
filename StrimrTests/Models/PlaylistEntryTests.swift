import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlaylistEntryTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `keeps entry IDs as row IDs when they are unique`() {
        let entries = makeEntries(["a", "b", "c"])

        #expect(entries.map(\.id) == ["a", "b", "c"])
        #expect(entries.map(\.entryID) == ["a", "b", "c"])
    }

    @Test func `makes row IDs unique when the server repeats an entry ID`() {
        let entries = makeEntries(["a", "b", "a", "a"])

        #expect(entries.map(\.id) == ["a", "b", "a#1", "a#2"])
        #expect(entries.map(\.entryID) == ["a", "b", "a", "a"])
    }

    @Test func `moving down gives the new index and the entry now before it`() throws {
        let result = try #require(PlaylistEntryMove.reordering(makeEntries(["a", "b", "c", "d"]), from: 0, to: 3))

        #expect(result.entries.map(\.entryID) == ["b", "c", "a", "d"])
        #expect(result.move == PlaylistEntryMove(entryID: "a", index: 2, previousEntryID: "c"))
    }

    @Test func `moving up to the top has no previous entry`() throws {
        let result = try #require(PlaylistEntryMove.reordering(makeEntries(["a", "b", "c"]), from: 2, to: 0))

        #expect(result.entries.map(\.entryID) == ["c", "a", "b"])
        #expect(result.move == PlaylistEntryMove(entryID: "c", index: 0, previousEntryID: nil))
    }

    @Test func `moving to the end lands on the last index`() throws {
        let result = try #require(PlaylistEntryMove.reordering(makeEntries(["a", "b", "c"]), from: 0, to: 3))

        #expect(result.entries.map(\.entryID) == ["b", "c", "a"])
        #expect(result.move == PlaylistEntryMove(entryID: "a", index: 2, previousEntryID: "c"))
    }

    @Test func `dropping an entry where it already is does nothing`() {
        let entries = makeEntries(["a", "b", "c"])

        #expect(PlaylistEntryMove.reordering(entries, from: 1, to: 1) == nil)
        #expect(PlaylistEntryMove.reordering(entries, from: 1, to: 2) == nil)
        #expect(PlaylistEntryMove.reordering(entries, from: 5, to: 0) == nil)
    }

    private func makeEntries(_ entryIDs: [String]) -> [PlaylistEntry] {
        PlaylistEntry.entries(entryIDs.map { entryID in
            (entryID: entryID, media: .playable(.make(id: "media-\(entryID)", server: server)))
        })
    }
}
