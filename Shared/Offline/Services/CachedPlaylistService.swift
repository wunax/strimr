import Foundation

/// Playlist contents stay readable offline; every change needs the server.
@MainActor
final class CachedPlaylistService: MediaPlaylistService {
    private let base: any MediaPlaylistService
    private let policy: OfflineCachePolicy

    init(base: any MediaPlaylistService, policy: OfflineCachePolicy) {
        self.base = base
        self.policy = policy
    }

    private var store: OfflineStore {
        policy.store
    }

    func playlistEntries(id: String) async throws -> [PlaylistEntry] {
        let key = "playlist:\(id)"
        let entries = try await policy.read(
            network: { try await base.playlistEntries(id: id) },
            write: { entries in
                store.store(
                    list: entries.map(\.media),
                    key: key,
                    payload: store.encode(entries.map(\.entryID)),
                    owner: policy.owner,
                )
            },
            fallback: { cachedEntries(key: key) },
        )
        let media = policy.overlayLocalProgress(entries.map(\.media))
        return zip(entries, media).map { PlaylistEntry(id: $0.id, entryID: $0.entryID, media: $1) }
    }

    func canEdit(_ playlist: PlaylistMediaItem) async throws -> Bool {
        try await policy.online { try await base.canEdit(playlist) }
    }

    func editablePlaylists() async throws -> [PlaylistMediaItem] {
        try await policy.online { try await base.editablePlaylists() }
    }

    func createPlaylist(title: String, itemID: String) async throws {
        try await policy.online { try await base.createPlaylist(title: title, itemID: itemID) }
    }

    func add(itemID: String, toPlaylist playlistID: String) async throws {
        try await policy.online { try await base.add(itemID: itemID, toPlaylist: playlistID) }
    }

    func remove(_ entry: PlaylistEntry, fromPlaylist playlistID: String) async throws {
        try await policy.online { try await base.remove(entry, fromPlaylist: playlistID) }
    }

    func move(_ move: PlaylistEntryMove, inPlaylist playlistID: String) async throws {
        try await policy.online { try await base.move(move, inPlaylist: playlistID) }
    }

    func rename(playlistID: String, to title: String) async throws {
        try await policy.online { try await base.rename(playlistID: playlistID, to: title) }
    }

    func delete(playlistID: String) async throws {
        try await policy.online { try await base.delete(playlistID: playlistID) }
    }

    private func cachedEntries(key: String) -> [PlaylistEntry]? {
        guard let snapshot = store.list(key: key, owner: policy.owner) else { return nil }
        let entryIDs = snapshot.payload.flatMap { store.decode([String].self, from: $0) }
        // Media evicted from the cache shift the list, so entry IDs no longer line up with it.
        let resolvedIDs = entryIDs?.count == snapshot.items.count ? entryIDs ?? [] : snapshot.items.map(\.id)
        return PlaylistEntry.entries(zip(resolvedIDs, snapshot.items).map { (entryID: $0, media: $1) })
    }
}
