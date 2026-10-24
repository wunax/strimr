import Foundation

/// One position in a playlist. The same media can sit at several positions.
struct PlaylistEntry: Identifiable, Hashable {
    /// Unique within the list, even when the server repeats an entry ID.
    let id: String
    /// What the server needs to remove or move this position: `playlistItemID` on Plex, `PlaylistItemId` on Jellyfin.
    let entryID: String
    let media: MediaDisplayItem

    /// Jellyfin 12 gives every occurrence of a media the media's own ID as entry ID.
    static func entries(_ values: [(entryID: String, media: MediaDisplayItem)]) -> [PlaylistEntry] {
        var occurrences: [String: Int] = [:]
        return values.map { value in
            let occurrence = occurrences[value.entryID, default: 0]
            occurrences[value.entryID] = occurrence + 1
            return PlaylistEntry(
                id: occurrence == 0 ? value.entryID : "\(value.entryID)#\(occurrence)",
                entryID: value.entryID,
                media: value.media,
            )
        }
    }
}

/// Where an entry lands once moved, in the two forms the servers expect.
struct PlaylistEntryMove: Equatable {
    let entryID: String
    /// Position in the reordered list, for Jellyfin.
    let index: Int
    /// Entry now just before it, nil when it becomes the first one, for Plex.
    let previousEntryID: String?
}

extension PlaylistEntryMove {
    /// - Parameter entries: the list after the move.
    init?(movedEntryAt index: Int, in entries: [PlaylistEntry]) {
        guard entries.indices.contains(index) else { return nil }
        entryID = entries[index].entryID
        self.index = index
        previousEntryID = index > 0 ? entries[index - 1].entryID : nil
    }

    /// Moves one entry the way `List.onMove` reports it: `destination` counts the entry still in place.
    /// Nil when the entry would stay where it is.
    static func reordering(
        _ entries: [PlaylistEntry],
        from source: Int,
        to destination: Int,
    ) -> (entries: [PlaylistEntry], move: PlaylistEntryMove)? {
        guard entries.indices.contains(source) else { return nil }
        let index = min(max(destination > source ? destination - 1 : destination, 0), entries.count - 1)
        guard index != source else { return nil }
        var reordered = entries
        reordered.insert(reordered.remove(at: source), at: index)
        return PlaylistEntryMove(movedEntryAt: index, in: reordered).map { (reordered, $0) }
    }
}
