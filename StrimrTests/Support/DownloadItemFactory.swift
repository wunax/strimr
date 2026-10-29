import Foundation
@testable import Strimr

extension DownloadItem {
    static func make(
        id: String,
        itemID: String,
        server: ServerIdentity,
        status: DownloadStatus = .completed,
        type: MediaKind = .movie,
        ownerID: String? = nil,
        createdAt: Date = Date(timeIntervalSince1970: 0),
    ) -> DownloadItem {
        DownloadItem(
            id: id,
            status: status,
            progress: status == .completed ? 1 : 0,
            bytesWritten: 0,
            totalBytes: 0,
            taskIdentifier: nil,
            remoteReference: nil,
            trackPreference: nil,
            errorMessage: nil,
            metadata: DownloadedMediaMetadata(
                identity: MediaIdentity(server: server, itemID: itemID),
                guid: "",
                type: type,
                title: itemID,
                summary: nil,
                genres: [],
                year: nil,
                duration: nil,
                viewCount: nil,
                contentRating: nil,
                studio: nil,
                tagline: nil,
                parentRatingKey: nil,
                grandparentRatingKey: nil,
                grandparentTitle: nil,
                parentTitle: nil,
                parentIndex: nil,
                index: nil,
                posterFileName: nil,
                videoFileName: "\(id).mp4",
                fileSize: nil,
                requestedQuality: .original,
                effectiveQuality: .original,
                audioTitle: nil,
                subtitleTitle: nil,
                createdAt: createdAt,
            ),
            ownerID: ownerID,
        )
    }
}
