import Foundation

@MainActor
final class PlexPlaylistService: MediaPlaylistService {
    private let context: PlexAPIContext
    private let server: ServerIdentity

    init(context: PlexAPIContext, server: ServerIdentity) {
        self.context = context
        self.server = server
    }

    func playlistEntries(id: String) async throws -> [PlaylistEntry] {
        let items = try await repository().getAllPlaylistItems(ratingKey: id)
        return Self.entries(from: items, server: server)
    }

    func canEdit(_ playlist: PlaylistMediaItem) async throws -> Bool {
        !playlist.isSmart
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        try await repository().getAllPlaylists(playlistType: "video", smart: false)
            .map { PlaylistMediaItem(plexItem: $0, server: server) }
    }

    func createPlaylist(title: String, itemID: String) async throws {
        try await repository().createPlaylist(title: title, itemRatingKey: itemID)
    }

    func add(itemID: String, toPlaylist playlistID: String) async throws {
        try await repository().addItem(ratingKey: itemID, toPlaylist: playlistID)
    }

    func remove(_ entry: PlaylistEntry, fromPlaylist playlistID: String) async throws {
        try await repository().removeItem(playlistItemID: entry.entryID, fromPlaylist: playlistID)
    }

    func move(_ move: PlaylistEntryMove, inPlaylist playlistID: String) async throws {
        try await repository().moveItem(
            playlistItemID: move.entryID,
            after: move.previousEntryID,
            inPlaylist: playlistID,
        )
    }

    func rename(playlistID: String, to title: String) async throws {
        try await repository().renamePlaylist(ratingKey: playlistID, title: title)
    }

    func delete(playlistID: String) async throws {
        try await repository().deletePlaylist(ratingKey: playlistID)
    }

    static func entries(from items: [PlexItem], server: ServerIdentity) -> [PlaylistEntry] {
        PlaylistEntry.entries(items.compactMap { item in
            guard let entryID = item.playlistItemID,
                  let media = MediaDisplayItem(plexItem: item, server: server)
            else { return nil }
            return (String(entryID), media)
        })
    }

    private func repository() throws -> PlaylistRepository {
        try PlaylistRepository(context: context)
    }
}
