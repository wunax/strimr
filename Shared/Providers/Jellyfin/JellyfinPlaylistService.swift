import Foundation

@MainActor
final class JellyfinPlaylistService: MediaPlaylistService {
    private let context: JellyfinAPIContext
    private let catalog: JellyfinCatalogService
    private let server: ServerIdentity

    init(context: JellyfinAPIContext, server: ServerIdentity) {
        self.context = context
        catalog = JellyfinCatalogService(context: context)
        self.server = server
    }

    func playlistEntries(id: String) async throws -> [PlaylistEntry] {
        try await Self.entries(from: catalog.playlistItems(id: id), server: server)
    }

    func canEdit(_ playlist: PlaylistMediaItem) async throws -> Bool {
        try await catalog.item(id: playlist.id).canDelete == true
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        let playlists = try await catalog.playlists()
            .filter { $0.mediaType == nil || $0.mediaType == "Video" }
            .compactMap { item -> PlaylistMediaItem? in
                guard case let .playlist(playlist) = MediaDisplayItem(jellyfinItem: item, server: server) else {
                    return nil
                }
                return playlist
            }
        // `CanDelete` is only trustworthy on a single item, so ownership is checked one playlist at a time.
        let editableIDs = await withTaskGroup(of: String?.self) { group in
            for playlist in playlists {
                group.addTask { [self] in
                    await (try? canEdit(playlist)) == true ? playlist.id : nil
                }
            }
            var ids = Set<String>()
            for await id in group {
                if let id {
                    ids.insert(id)
                }
            }
            return ids
        }
        return playlists.filter { editableIDs.contains($0.id) }
    }

    func createPlaylist(title: String, itemID: String) async throws {
        try await context.send(
            path: ["Playlists"],
            method: "POST",
            body: JSONEncoder().encode(JellyfinCreatePlaylistRequest(
                name: title,
                ids: [itemID],
                userID: userID(),
            )),
        )
    }

    func add(itemID: String, toPlaylist playlistID: String) async throws {
        let playlist: JellyfinPlaylistContent = try await context.get(path: ["Playlists", playlistID])
        // Unlike Plex, Jellyfin adds duplicates, and then cannot remove one occurrence without the others.
        guard !playlist.itemIDs.contains(itemID) else { return }
        try await context.send(
            path: ["Playlists", playlistID, "Items"],
            method: "POST",
            query: [
                URLQueryItem(name: "ids", value: itemID),
                URLQueryItem(name: "userId", value: userID()),
            ],
        )
    }

    func remove(_ entry: PlaylistEntry, fromPlaylist playlistID: String) async throws {
        try await context.send(
            path: ["Playlists", playlistID, "Items"],
            method: "DELETE",
            query: [URLQueryItem(name: "entryIds", value: entry.entryID)],
        )
    }

    func move(_ move: PlaylistEntryMove, inPlaylist playlistID: String) async throws {
        try await context.send(
            path: ["Playlists", playlistID, "Items", move.entryID, "Move", String(move.index)],
            method: "POST",
        )
    }

    func rename(playlistID: String, to title: String) async throws {
        try await context.send(
            path: ["Playlists", playlistID],
            method: "POST",
            body: JSONEncoder().encode(JellyfinUpdatePlaylistRequest(name: title)),
        )
    }

    func delete(playlistID: String) async throws {
        try await context.send(path: ["Items", playlistID], method: "DELETE")
    }

    static func entries(from items: [JellyfinItem], server: ServerIdentity) -> [PlaylistEntry] {
        PlaylistEntry.entries(items.compactMap { item in
            MediaDisplayItem(jellyfinItem: item, server: server).map { (item.playlistItemID ?? item.id, $0) }
        })
    }

    private func userID() throws -> String {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }
        return userID
    }
}

private nonisolated struct JellyfinCreatePlaylistRequest: Encodable {
    let name: String
    let ids: [String]
    let userID: String
    let mediaType = "Video"
    /// Jellyfin opens new playlists to every user unless told otherwise; Plex playlists stay private.
    let isPublic = false

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case ids = "Ids"
        case userID = "UserId"
        case mediaType = "MediaType"
        case isPublic = "IsPublic"
    }
}

private nonisolated struct JellyfinUpdatePlaylistRequest: Encodable {
    let name: String

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}

private nonisolated struct JellyfinPlaylistContent: Decodable {
    let itemIDs: [String]

    private enum CodingKeys: String, CodingKey {
        case itemIDs = "ItemIds"
    }
}
