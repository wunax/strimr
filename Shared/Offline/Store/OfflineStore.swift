import Foundation
import GRDB

struct OfflineListSnapshot {
    let items: [MediaDisplayItem]
    let payload: Data?
    let updatedAt: Date
}

struct OfflineStorageSizes: Equatable {
    var pinnedBytes: Int64 = 0
    var cacheBytes: Int64 = 0
}

private struct OfflineDetailPayload: Codable {
    var cast: [CastMember]
}

/// Single entry point to the offline databases. Encoding of domain models happens on the main actor; database
/// closures only manipulate plain records.
@MainActor
final class OfflineStore {
    let database: OfflineDatabase
    /// Ceiling of the browsing cache; eviction runs after every few megabytes written.
    var cacheLimit: Int64 = OfflineCacheLimit.mb500.bytes
    private var bytesWrittenSinceEviction: Int64 = 0
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    init(database: OfflineDatabase) {
        self.database = database
    }

    private var offline: DatabasePool {
        database.offline
    }

    private var cache: DatabasePool {
        database.cache
    }

    // MARK: - Owners

    func register(owner: MediaOwner) {
        let record = OwnerRecord(
            id: owner.id,
            provider: owner.server.provider.rawValue,
            serverID: owner.server.id,
            userID: owner.userID,
        )
        perform { try self.offline.write { db in try record.save(db) } }
    }

    func owner(id: String) -> MediaOwner? {
        let record = perform { try self.offline.read { db in try OwnerRecord.fetchOne(db, key: id) } } ?? nil
        guard let record, let provider = MediaProvider(rawValue: record.provider) else { return nil }
        return MediaOwner(server: ServerIdentity(provider: provider, id: record.serverID), userID: record.userID)
    }

    // MARK: - Downloads

    func allDownloads() throws -> [DownloadItem] {
        let records = try offline.read { db in
            try DownloadRecord.order(Column("createdAt")).fetchAll(db)
        }
        return records.compactMap(downloadItem(from:))
    }

    func save(downloads items: [DownloadItem]) throws {
        let records = try items.map(downloadRecord(from:))
        try offline.write { db in
            for record in records {
                try record.save(db)
            }
        }
    }

    func save(download item: DownloadItem) {
        guard let record = try? downloadRecord(from: item) else { return }
        perform { try self.offline.write { db in try record.save(db) } }
    }

    /// Removes a download row, then releases everything it pinned that no other download still references.
    func deleteDownload(id: String) {
        perform {
            let released = try self.offline.write { db -> [(String, String)] in
                let links = try DownloadLinkRecord.filter(Column("downloadID") == id).fetchAll(db)
                _ = try DownloadRecord.deleteOne(db, key: id)
                try DownloadLinkRecord.filter(Column("downloadID") == id).deleteAll(db)
                return try links.compactMap { link in
                    let stillReferenced = try DownloadLinkRecord
                        .filter(Column("ownerID") == link.ownerID && Column("itemID") == link.itemID)
                        .fetchCount(db) > 0
                    return stillReferenced ? nil : (link.ownerID, link.itemID)
                }
            }
            try self.release(pinned: released)
        }
    }

    func assignOwner(_ owner: MediaOwner, toUnownedDownloadsOn server: ServerIdentity) -> Int {
        perform {
            try self.offline.write { db in
                try DownloadRecord
                    .filter(Column("ownerID") == nil)
                    .filter(Column("provider") == server.provider.rawValue && Column("serverID") == server.id)
                    .updateAll(db, Column("ownerID").set(to: owner.id))
            }
        } ?? 0
    }

    private func downloadRecord(from item: DownloadItem) throws -> DownloadRecord {
        let metadata = item.metadata
        return try DownloadRecord(
            id: item.id,
            ownerID: item.ownerID,
            provider: item.identity?.server.provider.rawValue,
            serverID: item.identity?.server.id,
            itemID: item.itemID,
            status: item.status.rawValue,
            progress: item.progress,
            bytesWritten: item.bytesWritten,
            totalBytes: item.totalBytes,
            taskIdentifier: item.taskIdentifier,
            remoteReference: item.remoteReference.map { try encoder.encode($0) },
            trackPreference: item.trackPreference.map { try encoder.encode($0) },
            allowsCellularAccess: item.allowsCellularAccess,
            errorMessage: item.errorMessage,
            videoFileName: metadata.videoFileName,
            subtitleFileName: metadata.subtitleFileName,
            subtitleTitle: metadata.subtitleTitle,
            subtitleLanguage: metadata.subtitleLanguage,
            subtitleCodec: metadata.subtitleCodec,
            subtitleIsForced: metadata.subtitleIsForced,
            fileSize: metadata.fileSize,
            requestedQuality: metadata.requestedQuality.rawValue,
            effectiveQuality: metadata.effectiveQuality.rawValue,
            audioTitle: metadata.audioTitle,
            versionID: metadata.versionID,
            versionLabel: metadata.versionLabel,
            metadata: encoder.encode(metadata),
            enrichmentState: (item.enrichmentState ?? .pending).rawValue,
            createdAt: metadata.createdAt,
        )
    }

    private func downloadItem(from record: DownloadRecord) -> DownloadItem? {
        guard var metadata = try? decoder.decode(DownloadedMediaMetadata.self, from: record.metadata),
              let status = DownloadStatus(rawValue: record.status)
        else { return nil }
        metadata.videoFileName = record.videoFileName
        metadata.subtitleFileName = record.subtitleFileName
        metadata.subtitleTitle = record.subtitleTitle
        metadata.subtitleLanguage = record.subtitleLanguage
        metadata.subtitleCodec = record.subtitleCodec
        metadata.subtitleIsForced = record.subtitleIsForced
        metadata.fileSize = record.fileSize
        metadata.requestedQuality = TranscodeQualityPreset(rawValue: record.requestedQuality) ?? .original
        metadata.effectiveQuality = TranscodeQualityPreset(rawValue: record.effectiveQuality)
            ?? metadata.requestedQuality
        metadata.audioTitle = record.audioTitle
        metadata.versionID = record.versionID
        metadata.versionLabel = record.versionLabel
        return DownloadItem(
            id: record.id,
            status: status,
            progress: record.progress,
            bytesWritten: record.bytesWritten,
            totalBytes: record.totalBytes,
            taskIdentifier: record.taskIdentifier,
            remoteReference: record.remoteReference.flatMap {
                try? decoder.decode(MediaDownloadRemoteReference.self, from: $0)
            },
            trackPreference: record.trackPreference.flatMap {
                try? decoder.decode(MediaTrackPreference.self, from: $0)
            },
            allowsCellularAccess: record.allowsCellularAccess,
            errorMessage: record.errorMessage,
            metadata: metadata,
            ownerID: record.ownerID,
            enrichmentState: DownloadEnrichmentState(rawValue: record.enrichmentState) ?? .pending,
        )
    }

    /// Items of completed downloads for an owner, most recent first.
    func downloadedItemIDsByDate(owner: MediaOwner) -> [String] {
        perform {
            try self.offline.read { db in
                try String.fetchAll(
                    db,
                    DownloadRecord.select(Column("itemID"))
                        .filter(Column("ownerID") == owner.id && Column("status") == DownloadStatus.completed.rawValue)
                        .order(Column("createdAt").desc),
                )
            }
        } ?? []
    }

    // MARK: - Pinning

    static func artworkLinkID(_ key: String) -> String {
        "artwork:\(key)"
    }

    /// Links media and artwork to a download and moves their rows from the browsing cache to the pinned database.
    func pin(itemIDs: [String], artworkKeys: [String] = [], downloadID: String, owner: MediaOwner) {
        let linkIDs = Array(Set(itemIDs)) + Set(artworkKeys).map(Self.artworkLinkID)
        perform {
            try self.offline.write { db in
                for itemID in linkIDs {
                    try DownloadLinkRecord(downloadID: downloadID, ownerID: owner.id, itemID: itemID)
                        .insert(db, onConflict: .ignore)
                }
            }
            try self.movePinned(itemIDs: Array(Set(itemIDs)), artworkKeys: Array(Set(artworkKeys)), ownerID: owner.id)
        }
    }

    private func movePinned(itemIDs: [String], artworkKeys: [String], ownerID: String) throws {
        let mediaRows = try cache.read { db in
            try MediaRecord.filter(Column("ownerID") == ownerID && itemIDs.contains(Column("itemID"))).fetchAll(db)
        }
        let artworkRows = try cache.read { db in
            try ArtworkRecord
                .filter(Column("ownerID") == ownerID && artworkKeys.contains(Column("artworkKey")))
                .fetchAll(db)
        }
        try offline.write { db in
            for row in mediaRows {
                try row.insert(db, onConflict: .replace)
            }
        }
        for row in artworkRows {
            moveArtworkFile(row.fileName, from: database.cacheArtworkDirectory, to: database.pinnedArtworkDirectory)
        }
        try offline.write { db in
            for row in artworkRows {
                try row.insert(db, onConflict: .replace)
            }
        }
        try cache.write { db in
            try MediaRecord.filter(Column("ownerID") == ownerID && itemIDs.contains(Column("itemID"))).deleteAll(db)
            try ArtworkRecord.filter(Column("ownerID") == ownerID && artworkKeys.contains(Column("artworkKey")))
                .deleteAll(db)
        }
    }

    private func release(pinned links: [(ownerID: String, itemID: String)]) throws {
        let grouped = Dictionary(grouping: links, by: \.ownerID)
        for (ownerID, entries) in grouped {
            let artworkKeys = entries.compactMap { entry -> String? in
                guard entry.itemID.hasPrefix("artwork:") else { return nil }
                return String(entry.itemID.dropFirst("artwork:".count))
            }
            let itemIDs = entries.map(\.itemID).filter { !$0.hasPrefix("artwork:") }
            let mediaRows = try offline.read { db in
                try MediaRecord.filter(Column("ownerID") == ownerID && itemIDs.contains(Column("itemID"))).fetchAll(db)
            }
            let artworkRows = try offline.read { db in
                try ArtworkRecord
                    .filter(Column("ownerID") == ownerID && artworkKeys.contains(Column("artworkKey")))
                    .fetchAll(db)
            }
            try cache.write { db in
                for row in mediaRows {
                    try row.insert(db, onConflict: .replace)
                }
                for row in artworkRows {
                    try row.insert(db, onConflict: .replace)
                }
            }
            for row in artworkRows {
                moveArtworkFile(row.fileName, from: database.pinnedArtworkDirectory, to: database.cacheArtworkDirectory)
            }
            try offline.write { db in
                try MediaRecord.filter(Column("ownerID") == ownerID && itemIDs.contains(Column("itemID"))).deleteAll(db)
                try ArtworkRecord.filter(Column("ownerID") == ownerID && artworkKeys.contains(Column("artworkKey")))
                    .deleteAll(db)
            }
        }
    }

    private func moveArtworkFile(_ fileName: String, from source: URL, to destination: URL) {
        let sourceURL = source.appendingPathComponent(fileName)
        let destinationURL = destination.appendingPathComponent(fileName)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else { return }
        try? FileManager.default.removeItem(at: destinationURL)
        do {
            try FileManager.default.moveItem(at: sourceURL, to: destinationURL)
        } catch {
            ErrorReporter.capture(error)
        }
    }

    // MARK: - Media

    func store(media items: [MediaItem], owner: MediaOwner, libraryID: String? = nil) {
        store(displayItems: items.map(MediaDisplayItem.playable), owner: owner, libraryID: libraryID)
    }

    func store(displayItems items: [MediaDisplayItem], owner: MediaOwner, libraryID: String? = nil) {
        guard !items.isEmpty else { return }
        let now = Date()
        let records = items.compactMap { mediaRecord(for: $0, ownerID: owner.id, libraryID: libraryID, now: now) }
        let serverStates = items.compactMap(\.playableItem).map { item in
            WatchStateRecord(
                ownerID: owner.id,
                itemID: item.id,
                viewOffset: item.viewOffset,
                viewCount: item.viewCount ?? 0,
                played: item.watchState.isPlayed,
                lastViewedAt: item.lastViewedAt,
                source: WatchStateSource.server.rawValue,
            )
        }
        perform {
            try self.upsert(records)
            try self.offline.write { db in
                for state in serverStates where [MediaKind.movie.rawValue, MediaKind.episode.rawValue]
                    .contains(records.first(where: { $0.itemID == state.itemID })?.kind)
                {
                    // Local progress that is not yet synchronized wins over what the server returned.
                    let hasPendingLocal = try WatchStateRecord
                        .filter(Column("ownerID") == state.ownerID && Column("itemID") == state.itemID)
                        .filter(Column("source") == WatchStateSource.local.rawValue)
                        .fetchCount(db) > 0
                    if !hasPendingLocal {
                        try state.save(db)
                    }
                }
            }
        }
    }

    func store(detail content: MediaDetailContent, owner: MediaOwner) {
        var related = content.seasons + content.episodes
        if let parentSeries = content.parentSeries {
            related.append(parentSeries)
        }
        store(media: related, owner: owner)
        store(media: [content.media], owner: owner)
        guard let payload = try? encoder.encode(OfflineDetailPayload(cast: content.cast)) else { return }
        let itemID = content.media.id
        perform {
            for pool in [self.offline, self.cache] {
                try pool.write { db in
                    try db.execute(
                        sql: "UPDATE media SET detailPayload = ? WHERE ownerID = ? AND itemID = ?",
                        arguments: [payload, owner.id, itemID],
                    )
                }
            }
        }
    }

    func setLibraryID(_ libraryID: String, for itemIDs: [String], owner: MediaOwner) {
        perform {
            for pool in [self.offline, self.cache] {
                _ = try pool.write { db in
                    try MediaRecord.filter(Column("ownerID") == owner.id && itemIDs.contains(Column("itemID")))
                        .updateAll(db, Column("libraryID").set(to: libraryID))
                }
            }
        }
    }

    func removeMedia(itemID: String, owner: MediaOwner) {
        perform {
            try self.cache.write { db in
                _ = try MediaRecord.filter(Column("ownerID") == owner.id && Column("itemID") == itemID).deleteAll(db)
            }
        }
    }

    func media(id itemID: String, owner: MediaOwner) -> MediaItem? {
        mediaItems(ids: [itemID], owner: owner).first
    }

    func displayItem(id itemID: String, owner: MediaOwner) -> MediaDisplayItem? {
        displayItems(ids: [itemID], owner: owner).first
    }

    func mediaItems(ids: [String], owner: MediaOwner) -> [MediaItem] {
        displayItems(ids: ids, owner: owner).compactMap(\.playableItem)
    }

    /// Returns cached items in the order of `ids`, silently skipping unknown ones.
    func displayItems(ids: [String], owner: MediaOwner) -> [MediaDisplayItem] {
        guard !ids.isEmpty else { return [] }
        let records = fetchMedia(owner: owner, touch: true) {
            $0.filter(ids.contains(Column("itemID")))
        }
        let byID = Dictionary(records.map { ($0.itemID, $0) }, uniquingKeysWith: { first, _ in first })
        return decode(ids.compactMap { byID[$0] }, owner: owner)
    }

    func cast(for itemID: String, owner: MediaOwner) -> [CastMember]? {
        let records = fetchMedia(owner: owner, touch: false) { $0.filter(Column("itemID") == itemID) }
        guard let data = records.first?.detailPayload,
              let payload = try? decoder.decode(OfflineDetailPayload.self, from: data)
        else { return nil }
        return payload.cast
    }

    func children(of parentID: String, kind: MediaKind, owner: MediaOwner) -> [MediaItem] {
        let records = fetchMedia(owner: owner, touch: true) {
            $0.filter(Column("parentID") == parentID && Column("kind") == kind.rawValue)
        }
        return sortedByIndex(decode(records, owner: owner).compactMap(\.playableItem))
    }

    func episodes(ofSeries seriesID: String, owner: MediaOwner) -> [MediaItem] {
        let records = fetchMedia(owner: owner, touch: true) {
            $0.filter(Column("grandparentID") == seriesID && Column("kind") == MediaKind.episode.rawValue)
        }
        return decode(records, owner: owner).compactMap(\.playableItem).sorted { lhs, rhs in
            let lhsSeason = lhs.parentIndex ?? Int.max
            let rhsSeason = rhs.parentIndex ?? Int.max
            if lhsSeason != rhsSeason {
                return lhsSeason < rhsSeason
            }
            return (lhs.index ?? Int.max) < (rhs.index ?? Int.max)
        }
    }

    /// Top-level movies and series cached for a library, sorted locally by title.
    func libraryItems(libraryID: String, owner: MediaOwner, onlyIDs: Set<String>? = nil) -> [MediaDisplayItem] {
        let kinds = [MediaKind.movie.rawValue, MediaKind.series.rawValue]
        var records = fetchMedia(owner: owner, touch: false) {
            $0.filter(Column("libraryID") == libraryID && kinds.contains(Column("kind")))
        }
        if let onlyIDs {
            records = records.filter { onlyIDs.contains($0.itemID) }
        }
        return decode(records.sorted { $0.sortTitle < $1.sortTitle }, owner: owner)
    }

    /// Downloaded movies and series with downloaded episodes of a library. Downloads that are not enriched yet have
    /// no library and are left out.
    func downloadedLibraryItems(libraryID: String, owner: MediaOwner) -> [MediaDisplayItem] {
        let downloaded = mediaItems(ids: downloadedItemIDsByDate(owner: owner), owner: owner)
        let ids = Set(downloaded.compactMap { item -> String? in
            switch item.kind {
            case .movie:
                item.id
            case .episode:
                item.grandparentRatingKey
            default:
                nil
            }
        })
        return libraryItems(libraryID: libraryID, owner: owner, onlyIDs: ids)
    }

    func search(query: String, owner: MediaOwner) -> [MediaItem] {
        let folded = Self.fold(query)
        guard !folded.isEmpty else { return [] }
        let pattern = "%\(folded)%"
        let kinds = [MediaKind.movie, .series, .episode].map(\.rawValue)
        let records = fetchMedia(owner: owner, touch: false) {
            $0.filter(Column("searchTitle").like(pattern) && kinds.contains(Column("kind")))
        }
        return decode(records.sorted { $0.sortTitle < $1.sortTitle }, owner: owner).compactMap(\.playableItem)
    }

    /// Movies and episodes with a resume position not yet synchronized to the server, most recently viewed first.
    func locallyInProgressItems(owner: MediaOwner, limit: Int = 30) -> [MediaItem] {
        let states: [WatchStateRecord] = perform {
            try self.offline.read { db in
                try WatchStateRecord
                    .filter(Column("ownerID") == owner.id && Column("viewOffset") > 0 && Column("played") == false)
                    .filter(Column("source") == WatchStateSource.local.rawValue)
                    .order(Column("lastViewedAt").desc)
                    .limit(limit * 2)
                    .fetchAll(db)
            }
        } ?? []
        return Array(mediaItems(ids: states.map(\.itemID), owner: owner)
            .filter { $0.kind == .movie || $0.kind == .episode }
            .prefix(limit))
    }

    private func sortedByIndex(_ items: [MediaItem]) -> [MediaItem] {
        items.sorted { ($0.index ?? Int.max, $0.title) < ($1.index ?? Int.max, $1.title) }
    }

    private func fetchMedia(
        owner: MediaOwner,
        touch: Bool,
        filter: @escaping @Sendable (QueryInterfaceRequest<MediaRecord>) -> QueryInterfaceRequest<MediaRecord>,
    ) -> [MediaRecord] {
        let ownerID = owner.id
        let request: @Sendable (Database) throws -> [MediaRecord] = { db in
            try filter(MediaRecord.filter(Column("ownerID") == ownerID)).fetchAll(db)
        }
        let pinned = perform { try self.offline.read(request) } ?? []
        let pinnedIDs = Set(pinned.map(\.itemID))
        let cached = (perform { try self.cache.read(request) } ?? []).filter { !pinnedIDs.contains($0.itemID) }
        if touch, !cached.isEmpty {
            let ids = cached.map(\.itemID)
            let now = Date()
            perform {
                try self.cache.write { db in
                    try MediaRecord.filter(Column("ownerID") == ownerID && ids.contains(Column("itemID")))
                        .updateAll(db, Column("lastAccessedAt").set(to: now))
                }
            }
        }
        return pinned + cached
    }

    private func decode(_ records: [MediaRecord], owner: MediaOwner) -> [MediaDisplayItem] {
        let states = watchStates(itemIDs: records.map(\.itemID), owner: owner, localOnly: false)
        return records.compactMap { record in
            switch MediaKind(rawValue: record.kind) {
            case .collection:
                return (try? decoder.decode(CollectionMediaItem.self, from: record.payload))
                    .map { MediaDisplayItem.collection($0.assigning(server: owner.server)) }
            case .playlist:
                return (try? decoder.decode(PlaylistMediaItem.self, from: record.payload))
                    .map { MediaDisplayItem.playlist($0.assigning(server: owner.server)) }
            default:
                guard let item = try? decoder.decode(MediaItem.self, from: record.payload) else { return nil }
                return .playable(states[item.id].map { item.applying($0) } ?? item)
            }
        }
    }

    private func mediaRecord(
        for item: MediaDisplayItem,
        ownerID: String,
        libraryID: String?,
        now: Date,
    ) -> MediaRecord? {
        let payload: Data?
        let playable = item.playableItem
        switch item {
        case let .playable(media):
            payload = try? encoder.encode(media)
        case let .collection(collection):
            payload = try? encoder.encode(collection)
        case let .playlist(playlist):
            payload = try? encoder.encode(playlist)
        }
        guard let payload else { return nil }
        return MediaRecord(
            ownerID: ownerID,
            itemID: item.id,
            kind: item.type.rawValue,
            libraryID: libraryID ?? playable?.librarySectionID,
            parentID: playable?.parentRatingKey,
            grandparentID: playable?.grandparentRatingKey,
            title: item.title,
            sortTitle: Self.fold(item.title),
            searchTitle: Self.fold([item.title, playable?.grandparentTitle].compactMap(\.self).joined(separator: " ")),
            year: playable?.year,
            itemIndex: playable?.index,
            parentIndex: playable?.parentIndex,
            guid: playable?.guid,
            payload: payload,
            detailPayload: nil,
            lastAccessedAt: now,
            updatedAt: now,
            byteSize: Int64(payload.count),
        )
    }

    private func upsert(_ records: [MediaRecord]) throws {
        guard !records.isEmpty else { return }
        let ids = records.map(\.itemID)
        let ownerID = records[0].ownerID
        let pinnedIDs = try Set(offline.read { db in
            try String.fetchAll(
                db,
                MediaRecord.select(Column("itemID"))
                    .filter(Column("ownerID") == ownerID && ids.contains(Column("itemID"))),
            )
        })
        let pinned = records.filter { pinnedIDs.contains($0.itemID) }
        let cached = records.filter { !pinnedIDs.contains($0.itemID) }
        try offline.write { db in try Self.upsert(pinned, db: db) }
        try cache.write { db in try Self.upsert(cached, db: db) }
        didWriteToCache(bytes: cached.reduce(0) { $0 + $1.byteSize })
    }

    private func didWriteToCache(bytes: Int64) {
        bytesWrittenSinceEviction += bytes
        guard bytesWrittenSinceEviction > 5_000_000 else { return }
        bytesWrittenSinceEviction = 0
        evictCache(toFit: cacheLimit)
    }

    private nonisolated static func upsert(_ records: [MediaRecord], db: Database) throws {
        for record in records {
            try db.execute(
                sql: """
                INSERT INTO media (ownerID, itemID, kind, libraryID, parentID, grandparentID, title, sortTitle,
                    searchTitle, year, itemIndex, parentIndex, guid, payload, detailPayload, lastAccessedAt,
                    updatedAt, byteSize)
                VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, NULL, ?, ?, ?)
                ON CONFLICT(ownerID, itemID) DO UPDATE SET
                    kind = excluded.kind,
                    libraryID = COALESCE(excluded.libraryID, media.libraryID),
                    parentID = COALESCE(excluded.parentID, media.parentID),
                    grandparentID = COALESCE(excluded.grandparentID, media.grandparentID),
                    title = excluded.title,
                    sortTitle = excluded.sortTitle,
                    searchTitle = excluded.searchTitle,
                    year = excluded.year,
                    itemIndex = excluded.itemIndex,
                    parentIndex = excluded.parentIndex,
                    guid = excluded.guid,
                    payload = excluded.payload,
                    lastAccessedAt = excluded.lastAccessedAt,
                    updatedAt = excluded.updatedAt,
                    byteSize = excluded.byteSize
                """,
                arguments: [
                    record.ownerID, record.itemID, record.kind, record.libraryID, record.parentID,
                    record.grandparentID, record.title, record.sortTitle, record.searchTitle, record.year,
                    record.itemIndex, record.parentIndex, record.guid, record.payload, record.lastAccessedAt,
                    record.updatedAt, record.byteSize,
                ],
            )
        }
    }

    static func fold(_ value: String) -> String {
        value.folding(options: [.caseInsensitive, .diacriticInsensitive, .widthInsensitive], locale: nil)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    // MARK: - Libraries

    func store(libraries: [Library], owner: MediaOwner) {
        let now = Date()
        let records = libraries.enumerated().compactMap { position, library -> LibraryRecord? in
            guard let payload = try? encoder.encode(library) else { return nil }
            return LibraryRecord(
                ownerID: owner.id,
                libraryID: library.id,
                position: position,
                payload: payload,
                lastAccessedAt: now,
                updatedAt: now,
            )
        }
        perform {
            try self.cache.write { db in
                try LibraryRecord.filter(Column("ownerID") == owner.id).deleteAll(db)
                for record in records {
                    try record.insert(db)
                }
            }
        }
    }

    func store(pinnedLibrary library: Library, owner: MediaOwner) {
        guard let payload = try? encoder.encode(library) else { return }
        let record = LibraryRecord(
            ownerID: owner.id,
            libraryID: library.id,
            position: 0,
            payload: payload,
            lastAccessedAt: Date(),
            updatedAt: Date(),
        )
        perform { try self.offline.write { db in try record.save(db) } }
    }

    func libraries(owner: MediaOwner) -> [Library] {
        let request: @Sendable (Database) throws -> [LibraryRecord] = { db in
            try LibraryRecord.filter(Column("ownerID") == owner.id).order(Column("position")).fetchAll(db)
        }
        let cached = perform { try self.cache.read(request) } ?? []
        let cachedIDs = Set(cached.map(\.libraryID))
        let pinned = (perform { try self.offline.read(request) } ?? []).filter { !cachedIDs.contains($0.libraryID) }
        return (cached + pinned).compactMap {
            try? decoder.decode(Library.self, from: $0.payload).assigning(server: owner.server)
        }
    }

    // MARK: - List snapshots

    func store(list items: [MediaDisplayItem], key: String, payload: Data? = nil, owner: MediaOwner) {
        store(displayItems: items, owner: owner)
        guard let itemIDs = try? encoder.encode(items.map(\.id)) else { return }
        let record = ListSnapshotRecord(
            ownerID: owner.id,
            key: key,
            itemIDs: itemIDs,
            payload: payload,
            updatedAt: Date(),
            lastAccessedAt: Date(),
            byteSize: Int64(itemIDs.count + (payload?.count ?? 0)),
        )
        perform { try self.cache.write { db in try record.save(db) } }
    }

    func list(key: String, owner: MediaOwner) -> OfflineListSnapshot? {
        let record = perform {
            try self.cache.write { db -> ListSnapshotRecord? in
                guard var record = try ListSnapshotRecord.fetchOne(db, key: ["ownerID": owner.id, "key": key])
                else { return nil }
                record.lastAccessedAt = Date()
                try record.update(db)
                return record
            }
        } ?? nil
        guard let record, let ids = try? decoder.decode([String].self, from: record.itemIDs) else { return nil }
        return OfflineListSnapshot(
            items: displayItems(ids: ids, owner: owner),
            payload: record.payload,
            updatedAt: record.updatedAt,
        )
    }

    func encode(_ value: some Encodable) -> Data? {
        try? encoder.encode(value)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) -> T? {
        try? decoder.decode(type, from: data)
    }

    // MARK: - Watch state and progress journal

    func watchStates(itemIDs: [String], owner: MediaOwner, localOnly: Bool) -> [String: OfflineWatchState] {
        guard !itemIDs.isEmpty else { return [:] }
        let records: [WatchStateRecord] = perform {
            try self.offline.read { db in
                var request = WatchStateRecord
                    .filter(Column("ownerID") == owner.id && itemIDs.contains(Column("itemID")))
                if localOnly {
                    request = request.filter(Column("source") == WatchStateSource.local.rawValue)
                }
                return try request.fetchAll(db)
            }
        } ?? []
        return Dictionary(records.map { record in
            (record.itemID, OfflineWatchState(
                viewOffset: record.viewOffset,
                viewCount: record.viewCount,
                played: record.played,
                lastViewedAt: record.lastViewedAt,
                source: WatchStateSource(rawValue: record.source) ?? .server,
            ))
        }, uniquingKeysWith: { first, _ in first })
    }

    func watchState(itemID: String, owner: MediaOwner) -> OfflineWatchState? {
        watchStates(itemIDs: [itemID], owner: owner, localOnly: false)[itemID]
    }

    func setWatchState(_ state: OfflineWatchState, itemID: String, owner: MediaOwner) {
        let record = WatchStateRecord(
            ownerID: owner.id,
            itemID: itemID,
            viewOffset: state.viewOffset,
            viewCount: state.viewCount,
            played: state.played,
            lastViewedAt: state.lastViewedAt,
            source: state.source.rawValue,
        )
        perform { try self.offline.write { db in try record.save(db) } }
    }

    func appendJournal(
        itemID: String,
        owner: MediaOwner,
        position: TimeInterval,
        duration: TimeInterval?,
        event: ProgressJournalEvent,
        occurredAt: Date,
        syncedAt: Date?,
    ) -> Int64? {
        var record = ProgressJournalRecord(
            id: nil,
            ownerID: owner.id,
            itemID: itemID,
            position: position,
            duration: duration,
            event: event.rawValue,
            occurredAt: occurredAt,
            syncedAt: syncedAt,
            attempts: 0,
            lastError: nil,
        )
        return perform {
            try self.offline.write { db in
                if event == .progress || event == .pause {
                    // Only the latest position matters until it is synchronized.
                    try ProgressJournalRecord
                        .filter(Column("ownerID") == owner.id && Column("itemID") == itemID)
                        .filter(Column("syncedAt") == nil)
                        .filter([ProgressJournalEvent.progress.rawValue, ProgressJournalEvent.pause.rawValue]
                            .contains(Column("event")))
                        .deleteAll(db)
                }
                try record.insert(db)
                return record.id
            }
        } ?? nil
    }

    /// Pending journal entries for an owner, oldest first.
    func pendingJournal(owner: MediaOwner) -> [ProgressJournalRecord] {
        perform {
            try self.offline.read { db in
                try ProgressJournalRecord
                    .filter(Column("ownerID") == owner.id && Column("syncedAt") == nil)
                    .order(Column("occurredAt"), Column("id"))
                    .fetchAll(db)
            }
        } ?? []
    }

    func pendingJournalCount(owner: MediaOwner) -> Int {
        perform {
            try self.offline.read { db in
                try ProgressJournalRecord
                    .filter(Column("ownerID") == owner.id && Column("syncedAt") == nil)
                    .fetchCount(db)
            }
        } ?? 0
    }

    func markJournalSynced(ids: [Int64], at date: Date = Date()) {
        guard !ids.isEmpty else { return }
        perform {
            try self.offline.write { db in
                try ProgressJournalRecord.filter(ids.contains(Column("id")))
                    .updateAll(db, Column("syncedAt").set(to: date))
                // Synced history is only kept for a while; the journal is not an audit log.
                try ProgressJournalRecord
                    .filter(Column("syncedAt") != nil && Column("syncedAt") < date.addingTimeInterval(-7 * 86400))
                    .deleteAll(db)
            }
        }
    }

    func markJournalFailed(ids: [Int64], error: String) {
        guard !ids.isEmpty else { return }
        perform {
            try self.offline.write { db in
                try db.execute(
                    sql: "UPDATE progress_journal SET attempts = attempts + 1, lastError = ? WHERE id IN (\(ids.map { _ in "?" }.joined(separator: ",")))",
                    arguments: StatementArguments([error] + ids.map { $0 as (any DatabaseValueConvertible)? }),
                )
            }
        }
    }

    // MARK: - Artwork

    func artworkFileURL(key: String, owner: MediaOwner) -> URL? {
        let request: @Sendable (Database) throws -> ArtworkRecord? = { db in
            try ArtworkRecord.fetchOne(db, key: ["ownerID": owner.id, "artworkKey": key])
        }
        if let record = perform({ try self.offline.read(request) }) ?? nil {
            let url = database.pinnedArtworkDirectory.appendingPathComponent(record.fileName)
            if FileManager.default.fileExists(atPath: url.path) {
                return url
            }
        }
        guard let record = perform({ try self.cache.read(request) }) ?? nil else { return nil }
        let url = database.cacheArtworkDirectory.appendingPathComponent(record.fileName)
        guard FileManager.default.fileExists(atPath: url.path) else { return nil }
        let now = Date()
        perform {
            try self.cache.write { db in
                try ArtworkRecord.filter(Column("ownerID") == owner.id && Column("artworkKey") == key)
                    .updateAll(db, Column("lastAccessedAt").set(to: now))
            }
        }
        return url
    }

    func isArtworkPinned(key: String, owner: MediaOwner) -> Bool {
        (perform {
            try self.offline.read { db in
                try ArtworkRecord.filter(Column("ownerID") == owner.id && Column("artworkKey") == key)
                    .fetchCount(db) > 0
            }
        }) ?? false
    }

    /// Any stored size of an artwork, largest first; used offline when the exact size is missing.
    func artworkFileURL(pathPrefix: String, owner: MediaOwner) -> URL? {
        let pattern = pathPrefix.replacingOccurrences(of: "%", with: "\\%")
            .replacingOccurrences(of: "_", with: "\\_") + "%"
        let request: @Sendable (Database) throws -> [ArtworkRecord] = { db in
            try ArtworkRecord
                .filter(Column("ownerID") == owner.id)
                .filter(sql: "artworkKey LIKE ? ESCAPE '\\'", arguments: [pattern])
                .order(Column("byteSize").desc)
                .fetchAll(db)
        }
        let candidates = [
            ((perform { try self.offline.read(request) }) ?? [])
                .map { self.database.pinnedArtworkDirectory.appendingPathComponent($0.fileName) },
            ((perform { try self.cache.read(request) }) ?? [])
                .map { self.database.cacheArtworkDirectory.appendingPathComponent($0.fileName) },
        ].flatMap(\.self)
        return candidates.first { FileManager.default.fileExists(atPath: $0.path) }
    }

    func storeArtwork(_ data: Data, key: String, owner: MediaOwner, width: Int?, height: Int?, pinned: Bool) {
        let fileName = Self.artworkFileName(ownerID: owner.id, key: key)
        let directory = pinned ? database.pinnedArtworkDirectory : database.cacheArtworkDirectory
        do {
            try data.write(to: directory.appendingPathComponent(fileName), options: .atomic)
        } catch {
            ErrorReporter.capture(error)
            return
        }
        let record = ArtworkRecord(
            ownerID: owner.id,
            artworkKey: key,
            fileName: fileName,
            width: width,
            height: height,
            byteSize: Int64(data.count),
            lastAccessedAt: Date(),
        )
        perform { try (pinned ? self.offline : self.cache).write { db in try record.save(db) } }
        if !pinned {
            didWriteToCache(bytes: record.byteSize)
        }
    }

    private static func artworkFileName(ownerID: String, key: String) -> String {
        var hasher = StableHasher()
        hasher.combine(ownerID)
        hasher.combine(key)
        return hasher.hexDigest + ".img"
    }

    // MARK: - Sizes and eviction

    func storageSizes() -> OfflineStorageSizes {
        let sql = """
        SELECT (SELECT IFNULL(SUM(byteSize), 0) FROM media) + (SELECT IFNULL(SUM(byteSize), 0) FROM artwork)
        """
        let pinned = perform { try self.offline.read { db in try Int64.fetchOne(db, sql: sql) } } ?? nil
        let cached = perform {
            try self.cache.read { db in
                try Int64.fetchOne(db, sql: sql + " + (SELECT IFNULL(SUM(byteSize), 0) FROM list_snapshot)")
            }
        } ?? nil
        return OfflineStorageSizes(pinnedBytes: pinned ?? 0, cacheBytes: cached ?? 0)
    }

    /// Evicts least recently used browsing-cache entries until the cache fits within `limit` bytes.
    func evictCache(toFit limit: Int64) {
        var total = storageSizes().cacheBytes
        guard total > limit else { return }
        let target = Int64(Double(limit) * 0.9)
        let batch = 200
        while total > target {
            let removed = perform { () -> Int64 in
                try self.cache.write { db in
                    let artwork = try ArtworkRecord.order(Column("lastAccessedAt")).limit(batch).fetchAll(db)
                    let media = try MediaRecord.order(Column("lastAccessedAt")).limit(batch).fetchAll(db)
                    let lists = try ListSnapshotRecord.order(Column("lastAccessedAt")).limit(batch / 4).fetchAll(db)
                    var removedBytes: Int64 = 0
                    for record in artwork {
                        try record.delete(db)
                        try? FileManager.default.removeItem(
                            at: self.database.cacheArtworkDirectory.appendingPathComponent(record.fileName),
                        )
                        removedBytes += record.byteSize
                    }
                    for record in media {
                        try record.delete(db)
                        removedBytes += record.byteSize
                    }
                    for record in lists {
                        try record.delete(db)
                        removedBytes += record.byteSize
                    }
                    return removedBytes
                }
            } ?? 0
            guard removed > 0 else { break }
            total -= removed
        }
    }

    func clearCache(owner: MediaOwner? = nil) {
        perform {
            try self.cache.write { db in
                if let owner {
                    let files = try String.fetchAll(
                        db,
                        ArtworkRecord.select(Column("fileName")).filter(Column("ownerID") == owner.id),
                    )
                    for file in files {
                        try? FileManager.default.removeItem(
                            at: self.database.cacheArtworkDirectory.appendingPathComponent(file),
                        )
                    }
                    for table in ["media", "library", "list_snapshot", "artwork"] {
                        try db.execute(sql: "DELETE FROM \(table) WHERE ownerID = ?", arguments: [owner.id])
                    }
                } else {
                    for table in ["media", "library", "list_snapshot", "artwork"] {
                        try db.execute(sql: "DELETE FROM \(table)")
                    }
                }
            }
            if owner == nil {
                let directory = self.database.cacheArtworkDirectory
                for url in (try? FileManager.default.contentsOfDirectory(
                    at: directory,
                    includingPropertiesForKeys: nil,
                )) ?? [] {
                    try? FileManager.default.removeItem(at: url)
                }
            }
        }
    }

    /// Deletes everything pinned for an owner (media, artwork, journal, watch state). Download rows are removed
    /// separately by the download manager, which also owns the files.
    func deletePinnedData(owner: MediaOwner) {
        perform {
            try self.offline.write { db in
                let files = try String.fetchAll(
                    db,
                    ArtworkRecord.select(Column("fileName")).filter(Column("ownerID") == owner.id),
                )
                for file in files {
                    try? FileManager.default.removeItem(
                        at: self.database.pinnedArtworkDirectory.appendingPathComponent(file),
                    )
                }
                for table in ["media", "library", "artwork", "watch_state", "progress_journal", "download_link"] {
                    try db.execute(sql: "DELETE FROM \(table) WHERE ownerID = ?", arguments: [owner.id])
                }
            }
        }
    }

    // MARK: - Helpers

    @discardableResult
    private func perform<T>(_ work: () throws -> T) -> T? {
        do {
            return try work()
        } catch {
            ErrorReporter.capture(error)
            return nil
        }
    }
}

extension MediaItem {
    func applying(_ state: OfflineWatchState) -> MediaItem {
        let played = state.played || state.viewCount > 0
        let isEpisodeOrMovie = kind == .movie || kind == .episode || kind == .clip
        guard isEpisodeOrMovie else { return self }
        let offset = played && (state.viewOffset ?? 0) <= 0 ? nil : state.viewOffset
        return MediaItem(
            id: id,
            identity: identity,
            guid: guid,
            summary: summary,
            title: title,
            type: type,
            parentRatingKey: parentRatingKey,
            grandparentRatingKey: grandparentRatingKey,
            genres: genres,
            year: year,
            duration: duration,
            videoResolution: videoResolution,
            rating: rating,
            ratings: ratings,
            contentRating: contentRating,
            studio: studio,
            tagline: tagline,
            thumbPath: thumbPath,
            artPath: artPath,
            artworkCornerColors: artworkCornerColors,
            viewOffset: offset.flatMap { $0 > 0 ? $0 : nil },
            viewCount: state.viewCount,
            childCount: childCount,
            leafCount: leafCount,
            viewedLeafCount: viewedLeafCount,
            watchState: MediaWatchState(
                isPlayed: played,
                playCount: state.viewCount,
                resumePosition: offset,
                unplayedItemCount: watchState.unplayedItemCount,
                isFavorite: watchState.isFavorite,
            ),
            grandparentTitle: grandparentTitle,
            parentTitle: parentTitle,
            parentIndex: parentIndex,
            index: index,
            grandparentThumbPath: grandparentThumbPath,
            grandparentArtPath: grandparentArtPath,
            parentThumbPath: parentThumbPath,
            librarySectionID: librarySectionID,
            lastViewedAt: state.lastViewedAt ?? lastViewedAt,
        )
    }
}

/// FNV-1a based digest used for artwork file names; stable across launches unlike `Hasher`.
private struct StableHasher {
    private var value: UInt64 = 0xCBF2_9CE4_8422_2325
    private var secondary: UInt64 = 0x8422_2325_CBF2_9CE4

    mutating func combine(_ string: String) {
        for byte in string.utf8 + [0] {
            value ^= UInt64(byte)
            value = value &* 0x100_0000_01B3
            secondary = (secondary ^ UInt64(byte)) &* 0x100_0000_01B3 &+ 0x9E37_79B9
        }
    }

    var hexDigest: String {
        String(format: "%016llx%016llx", value, secondary)
    }
}
