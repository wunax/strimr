import Foundation
import GRDB

/// Two SQLite files: `offline.sqlite` (Application Support) holds everything downloads depend on and must never be
/// purged by the OS; `cache.sqlite` (Caches) holds the evictable browsing cache.
final nonisolated class OfflineDatabase: Sendable {
    let offline: DatabasePool
    let cache: DatabasePool
    let pinnedArtworkDirectory: URL
    let cacheArtworkDirectory: URL

    init(fileManager: FileManager = .default) throws {
        let applicationSupport = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        let caches = fileManager.urls(for: .cachesDirectory, in: .userDomainMask)[0]
        let offlineDirectory = applicationSupport.appendingPathComponent("Offline", isDirectory: true)
        let cacheDirectory = caches.appendingPathComponent("Offline", isDirectory: true)
        pinnedArtworkDirectory = applicationSupport.appendingPathComponent("OfflineArtwork", isDirectory: true)
        cacheArtworkDirectory = caches.appendingPathComponent("Artwork", isDirectory: true)

        for directory in [offlineDirectory, cacheDirectory, pinnedArtworkDirectory, cacheArtworkDirectory] {
            try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        }
        try Self.excludeFromBackup(offlineDirectory)
        try Self.excludeFromBackup(pinnedArtworkDirectory)

        offline = try DatabasePool(path: offlineDirectory.appendingPathComponent("offline.sqlite").path)
        try Self.offlineMigrator.migrate(offline)

        cache = try Self.openCache(
            path: cacheDirectory.appendingPathComponent("cache.sqlite").path,
            artworkDirectory: cacheArtworkDirectory,
            fileManager: fileManager,
        )
    }

    private static func openCache(
        path: String,
        artworkDirectory: URL,
        fileManager: FileManager,
    ) throws -> DatabasePool {
        do {
            let pool = try DatabasePool(path: path)
            try cacheMigrator.migrate(pool)
            return pool
        } catch {
            // The browsing cache is disposable: a corrupted or incompatible file is simply recreated.
            for suffix in ["", "-wal", "-shm"] {
                try? fileManager.removeItem(atPath: path + suffix)
            }
            try? fileManager.removeItem(at: artworkDirectory)
            try fileManager.createDirectory(at: artworkDirectory, withIntermediateDirectories: true)
            let pool = try DatabasePool(path: path)
            try cacheMigrator.migrate(pool)
            return pool
        }
    }

    private static func excludeFromBackup(_ url: URL) throws {
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableURL = url
        try mutableURL.setResourceValues(values)
    }

    private static func createMediaTables(_ db: Database) throws {
        try db.create(table: "media") { table in
            table.column("ownerID", .text).notNull()
            table.column("itemID", .text).notNull()
            table.column("kind", .text).notNull()
            table.column("libraryID", .text)
            table.column("parentID", .text)
            table.column("grandparentID", .text)
            table.column("title", .text).notNull()
            table.column("sortTitle", .text).notNull()
            table.column("searchTitle", .text).notNull()
            table.column("year", .integer)
            table.column("itemIndex", .integer)
            table.column("parentIndex", .integer)
            table.column("guid", .text)
            table.column("payload", .blob).notNull()
            table.column("detailPayload", .blob)
            table.column("lastAccessedAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.column("byteSize", .integer).notNull()
            table.primaryKey(["ownerID", "itemID"])
        }
        try db.create(index: "media_parent", on: "media", columns: ["ownerID", "parentID"])
        try db.create(index: "media_grandparent", on: "media", columns: ["ownerID", "grandparentID"])
        try db.create(index: "media_library", on: "media", columns: ["ownerID", "libraryID"])
        try db.create(index: "media_access", on: "media", columns: ["lastAccessedAt"])

        try db.create(table: "library") { table in
            table.column("ownerID", .text).notNull()
            table.column("libraryID", .text).notNull()
            table.column("position", .integer).notNull()
            table.column("payload", .blob).notNull()
            table.column("lastAccessedAt", .datetime).notNull()
            table.column("updatedAt", .datetime).notNull()
            table.primaryKey(["ownerID", "libraryID"])
        }

        try db.create(table: "artwork") { table in
            table.column("ownerID", .text).notNull()
            table.column("artworkKey", .text).notNull()
            table.column("fileName", .text).notNull()
            table.column("width", .integer)
            table.column("height", .integer)
            table.column("byteSize", .integer).notNull()
            table.column("lastAccessedAt", .datetime).notNull()
            table.primaryKey(["ownerID", "artworkKey"])
        }
        try db.create(index: "artwork_access", on: "artwork", columns: ["lastAccessedAt"])
    }

    private static var offlineMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "owner") { table in
                table.primaryKey("id", .text)
                table.column("provider", .text).notNull()
                table.column("serverID", .text).notNull()
                table.column("userID", .text).notNull()
            }

            try db.create(table: "download") { table in
                table.primaryKey("id", .text)
                table.column("ownerID", .text)
                table.column("provider", .text)
                table.column("serverID", .text)
                table.column("itemID", .text).notNull()
                table.column("status", .text).notNull()
                table.column("progress", .double).notNull()
                table.column("bytesWritten", .integer).notNull()
                table.column("totalBytes", .integer).notNull()
                table.column("taskIdentifier", .integer)
                table.column("remoteReference", .blob)
                table.column("trackPreference", .blob)
                table.column("allowsCellularAccess", .boolean)
                table.column("errorMessage", .text)
                table.column("videoFileName", .text).notNull()
                table.column("subtitleFileName", .text)
                table.column("subtitleTitle", .text)
                table.column("subtitleLanguage", .text)
                table.column("subtitleCodec", .text)
                table.column("subtitleIsForced", .boolean).notNull()
                table.column("fileSize", .integer)
                table.column("requestedQuality", .text).notNull()
                table.column("effectiveQuality", .text).notNull()
                table.column("audioTitle", .text)
                table.column("metadata", .blob).notNull()
                table.column("enrichmentState", .text).notNull()
                table.column("createdAt", .datetime).notNull()
            }
            try db.create(index: "download_owner", on: "download", columns: ["ownerID"])

            try db.create(table: "download_link") { table in
                table.column("downloadID", .text).notNull()
                    .references("download", onDelete: .cascade)
                table.column("ownerID", .text).notNull()
                table.column("itemID", .text).notNull()
                table.primaryKey(["downloadID", "itemID"])
            }
            try db.create(index: "download_link_item", on: "download_link", columns: ["ownerID", "itemID"])

            try db.create(table: "progress_journal") { table in
                table.autoIncrementedPrimaryKey("id")
                table.column("ownerID", .text).notNull()
                table.column("itemID", .text).notNull()
                table.column("position", .double).notNull()
                table.column("duration", .double)
                table.column("event", .text).notNull()
                table.column("occurredAt", .datetime).notNull()
                table.column("syncedAt", .datetime)
                table.column("attempts", .integer).notNull().defaults(to: 0)
                table.column("lastError", .text)
            }
            try db.create(index: "progress_journal_pending", on: "progress_journal", columns: ["ownerID", "syncedAt"])

            try db.create(table: "watch_state") { table in
                table.column("ownerID", .text).notNull()
                table.column("itemID", .text).notNull()
                table.column("viewOffset", .double)
                table.column("viewCount", .integer).notNull()
                table.column("played", .boolean).notNull()
                table.column("lastViewedAt", .datetime)
                table.column("source", .text).notNull()
                table.primaryKey(["ownerID", "itemID"])
            }

            try createMediaTables(db)
        }
        migrator.registerMigration("v2") { db in
            try db.alter(table: "download") { table in
                table.add(column: "versionID", .text)
                table.add(column: "versionLabel", .text)
            }
        }
        return migrator
    }

    private static var cacheMigrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        // The browsing cache can be thrown away on schema changes instead of being migrated.
        migrator.eraseDatabaseOnSchemaChange = true
        migrator.registerMigration("v1") { db in
            try createMediaTables(db)
            try db.create(table: "list_snapshot") { table in
                table.column("ownerID", .text).notNull()
                table.column("key", .text).notNull()
                table.column("itemIDs", .blob).notNull()
                table.column("payload", .blob)
                table.column("updatedAt", .datetime).notNull()
                table.column("lastAccessedAt", .datetime).notNull()
                table.column("byteSize", .integer).notNull()
                table.primaryKey(["ownerID", "key"])
            }
        }
        return migrator
    }
}
