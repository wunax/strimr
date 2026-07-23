import Foundation

enum DownloadStatus: String, Codable, Hashable {
    case queued
    case downloading
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .downloading:
            true
        case .completed, .failed:
            false
        }
    }
}

struct DownloadedMediaMetadata: Codable, Hashable {
    var ratingKey: String
    var guid: String
    var type: PlexItemType
    var title: String
    var summary: String?
    var genres: [String]
    var year: Int?
    var duration: TimeInterval?
    var contentRating: String?
    var studio: String?
    var tagline: String?
    var parentRatingKey: String?
    var grandparentRatingKey: String?
    var grandparentTitle: String?
    var parentTitle: String?
    var parentIndex: Int?
    var index: Int?
    var posterFileName: String?
    var videoFileName: String
    var fileSize: Int64?
    var createdAt: Date

    var subtitle: String? {
        switch type {
        case .episode:
            if let grandparentTitle, let parentIndex, let index {
                return "\(grandparentTitle) • S\(parentIndex)E\(index)"
            }
            return grandparentTitle ?? parentTitle
        case .movie:
            return year.map(String.init)
        case .season:
            return parentTitle
        case .show:
            return nil
        case .collection, .playlist, .unknown:
            return nil
        }
    }
}

struct DownloadItem: Codable, Identifiable, Hashable {
    var id: String
    var status: DownloadStatus
    var progress: Double
    var bytesWritten: Int64
    var totalBytes: Int64
    var taskIdentifier: Int?
    var errorMessage: String?
    var metadata: DownloadedMediaMetadata

    var ratingKey: String {
        metadata.ratingKey
    }

    var isPlayable: Bool {
        status == .completed
    }

    var createdAt: Date {
        metadata.createdAt
    }
}

struct DownloadStorageSummary: Equatable {
    var totalBytes: Int64
    var usedBytes: Int64
    var availableBytes: Int64
    var downloadsBytes: Int64

    static let empty = DownloadStorageSummary(
        totalBytes: 0,
        usedBytes: 0,
        availableBytes: 0,
        downloadsBytes: 0,
    )
}
