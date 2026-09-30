import Foundation
import GRDB

nonisolated struct OwnerRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "owner"

    var id: String
    var provider: String
    var serverID: String
    var userID: String
}

nonisolated struct DownloadRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download"

    var id: String
    var ownerID: String?
    var provider: String?
    var serverID: String?
    var itemID: String
    var status: String
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var taskIdentifier: Int?
    var remoteReference: Data?
    var trackPreference: Data?
    var allowsCellularAccess: Bool?
    var errorMessage: String?
    var videoFileName: String
    var subtitleFileName: String?
    var subtitleTitle: String?
    var subtitleLanguage: String?
    var subtitleCodec: String?
    var subtitleIsForced: Bool
    var fileSize: Int64?
    var requestedQuality: String
    var effectiveQuality: String
    var audioTitle: String?
    var metadata: Data
    var enrichmentState: String
    var createdAt: Date
}

nonisolated struct DownloadLinkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "download_link"

    var downloadID: String
    var ownerID: String
    var itemID: String
}

nonisolated struct MediaRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "media"

    var ownerID: String
    var itemID: String
    var kind: String
    var libraryID: String?
    var parentID: String?
    var grandparentID: String?
    var title: String
    var sortTitle: String
    var searchTitle: String
    var year: Int?
    var itemIndex: Int?
    var parentIndex: Int?
    var guid: String?
    var payload: Data
    var detailPayload: Data?
    var lastAccessedAt: Date
    var updatedAt: Date
    var byteSize: Int64
}

nonisolated struct LibraryRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "library"

    var ownerID: String
    var libraryID: String
    var position: Int
    var payload: Data
    var lastAccessedAt: Date
    var updatedAt: Date
}

nonisolated struct ListSnapshotRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "list_snapshot"

    var ownerID: String
    var key: String
    var itemIDs: Data
    var payload: Data?
    var updatedAt: Date
    var lastAccessedAt: Date
    var byteSize: Int64
}

nonisolated struct ArtworkRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "artwork"

    var ownerID: String
    var artworkKey: String
    var fileName: String
    var width: Int?
    var height: Int?
    var byteSize: Int64
    var lastAccessedAt: Date
}

nonisolated struct WatchStateRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "watch_state"

    var ownerID: String
    var itemID: String
    var viewOffset: Double?
    var viewCount: Int
    var played: Bool
    var lastViewedAt: Date?
    var source: String
}

nonisolated struct ProgressJournalRecord: Codable, FetchableRecord, MutablePersistableRecord {
    static let databaseTableName = "progress_journal"

    var id: Int64?
    var ownerID: String
    var itemID: String
    var position: Double
    var duration: Double?
    var event: String
    var occurredAt: Date
    var syncedAt: Date?
    var attempts: Int
    var lastError: String?

    mutating func didInsert(_ inserted: InsertionSuccess) {
        id = inserted.rowID
    }
}
