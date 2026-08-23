import Foundation

enum DownloadStatus: String, Codable, Hashable {
    case queued
    case preparing
    case downloading
    case completed
    case failed

    var isActive: Bool {
        switch self {
        case .queued, .preparing, .downloading:
            true
        case .completed, .failed:
            false
        }
    }
}

struct DownloadedMediaMetadata: Codable, Hashable {
    var identity: MediaIdentity?
    var itemID: String
    var guid: String
    var type: MediaKind
    var title: String
    var summary: String?
    var genres: [String]
    var year: Int?
    var duration: TimeInterval?
    var viewCount: Int?
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
    var requestedQuality: TranscodeQualityPreset
    var effectiveQuality: TranscodeQualityPreset
    var audioTitle: String?
    var subtitleTitle: String?
    var subtitleFileName: String?
    var subtitleLanguage: String?
    var subtitleCodec: String?
    var subtitleIsForced: Bool
    var createdAt: Date

    init(
        identity: MediaIdentity,
        guid: String,
        type: MediaKind,
        title: String,
        summary: String?,
        genres: [String],
        year: Int?,
        duration: TimeInterval?,
        viewCount: Int?,
        contentRating: String?,
        studio: String?,
        tagline: String?,
        parentRatingKey: String?,
        grandparentRatingKey: String?,
        grandparentTitle: String?,
        parentTitle: String?,
        parentIndex: Int?,
        index: Int?,
        posterFileName: String?,
        videoFileName: String,
        fileSize: Int64?,
        requestedQuality: TranscodeQualityPreset,
        effectiveQuality: TranscodeQualityPreset,
        audioTitle: String?,
        subtitleTitle: String?,
        createdAt: Date,
    ) {
        self.identity = identity
        itemID = identity.itemID
        self.guid = guid
        self.type = type
        self.title = title
        self.summary = summary
        self.genres = genres
        self.year = year
        self.duration = duration
        self.viewCount = viewCount
        self.contentRating = contentRating
        self.studio = studio
        self.tagline = tagline
        self.parentRatingKey = parentRatingKey
        self.grandparentRatingKey = grandparentRatingKey
        self.grandparentTitle = grandparentTitle
        self.parentTitle = parentTitle
        self.parentIndex = parentIndex
        self.index = index
        self.posterFileName = posterFileName
        self.videoFileName = videoFileName
        self.fileSize = fileSize
        self.requestedQuality = requestedQuality
        self.effectiveQuality = effectiveQuality
        self.audioTitle = audioTitle
        self.subtitleTitle = subtitleTitle
        subtitleFileName = nil
        subtitleLanguage = nil
        subtitleCodec = nil
        subtitleIsForced = false
        self.createdAt = createdAt
    }

    private enum CodingKeys: String, CodingKey {
        case identity
        case itemID
        case provider
        case serverIdentifier
        case ratingKey
        case guid
        case type
        case title
        case summary
        case genres
        case year
        case duration
        case viewCount
        case contentRating
        case studio
        case tagline
        case parentRatingKey
        case grandparentRatingKey
        case grandparentTitle
        case parentTitle
        case parentIndex
        case index
        case posterFileName
        case videoFileName
        case fileSize
        case requestedQuality
        case effectiveQuality
        case audioTitle
        case subtitleTitle
        case subtitleFileName
        case subtitleLanguage
        case subtitleCodec
        case subtitleIsForced
        case createdAt
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        itemID = try container.decodeIfPresent(String.self, forKey: .itemID)
            ?? container.decode(String.self, forKey: .ratingKey)

        if let decodedIdentity = try container.decodeIfPresent(MediaIdentity.self, forKey: .identity) {
            identity = decodedIdentity
            itemID = decodedIdentity.itemID
        } else if
            let provider = try container.decodeIfPresent(MediaProvider.self, forKey: .provider),
            let serverIdentifier = try container.decodeIfPresent(String.self, forKey: .serverIdentifier)
        {
            identity = MediaIdentity(
                server: ServerIdentity(provider: provider, id: serverIdentifier),
                itemID: itemID,
            )
        } else {
            identity = nil
        }

        guid = try container.decode(String.self, forKey: .guid)
        type = try container.decode(MediaKind.self, forKey: .type)
        title = try container.decode(String.self, forKey: .title)
        summary = try container.decodeIfPresent(String.self, forKey: .summary)
        genres = try container.decode([String].self, forKey: .genres)
        year = try container.decodeIfPresent(Int.self, forKey: .year)
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        viewCount = try container.decodeIfPresent(Int.self, forKey: .viewCount)
        contentRating = try container.decodeIfPresent(String.self, forKey: .contentRating)
        studio = try container.decodeIfPresent(String.self, forKey: .studio)
        tagline = try container.decodeIfPresent(String.self, forKey: .tagline)
        parentRatingKey = try container.decodeIfPresent(String.self, forKey: .parentRatingKey)
        grandparentRatingKey = try container.decodeIfPresent(String.self, forKey: .grandparentRatingKey)
        grandparentTitle = try container.decodeIfPresent(String.self, forKey: .grandparentTitle)
        parentTitle = try container.decodeIfPresent(String.self, forKey: .parentTitle)
        parentIndex = try container.decodeIfPresent(Int.self, forKey: .parentIndex)
        index = try container.decodeIfPresent(Int.self, forKey: .index)
        posterFileName = try container.decodeIfPresent(String.self, forKey: .posterFileName)
        videoFileName = try container.decode(String.self, forKey: .videoFileName)
        fileSize = try container.decodeIfPresent(Int64.self, forKey: .fileSize)
        requestedQuality = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .requestedQuality,
        ) ?? .original
        effectiveQuality = try container.decodeIfPresent(
            TranscodeQualityPreset.self,
            forKey: .effectiveQuality,
        ) ?? requestedQuality
        audioTitle = try container.decodeIfPresent(String.self, forKey: .audioTitle)
        subtitleTitle = try container.decodeIfPresent(String.self, forKey: .subtitleTitle)
        subtitleFileName = try container.decodeIfPresent(String.self, forKey: .subtitleFileName)
        subtitleLanguage = try container.decodeIfPresent(String.self, forKey: .subtitleLanguage)
        subtitleCodec = try container.decodeIfPresent(String.self, forKey: .subtitleCodec)
        subtitleIsForced = try container.decodeIfPresent(Bool.self, forKey: .subtitleIsForced) ?? false
        createdAt = try container.decode(Date.self, forKey: .createdAt)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encodeIfPresent(identity, forKey: .identity)
        try container.encode(itemID, forKey: .itemID)
        try container.encode(guid, forKey: .guid)
        try container.encode(type, forKey: .type)
        try container.encode(title, forKey: .title)
        try container.encodeIfPresent(summary, forKey: .summary)
        try container.encode(genres, forKey: .genres)
        try container.encodeIfPresent(year, forKey: .year)
        try container.encodeIfPresent(duration, forKey: .duration)
        try container.encodeIfPresent(viewCount, forKey: .viewCount)
        try container.encodeIfPresent(contentRating, forKey: .contentRating)
        try container.encodeIfPresent(studio, forKey: .studio)
        try container.encodeIfPresent(tagline, forKey: .tagline)
        try container.encodeIfPresent(parentRatingKey, forKey: .parentRatingKey)
        try container.encodeIfPresent(grandparentRatingKey, forKey: .grandparentRatingKey)
        try container.encodeIfPresent(grandparentTitle, forKey: .grandparentTitle)
        try container.encodeIfPresent(parentTitle, forKey: .parentTitle)
        try container.encodeIfPresent(parentIndex, forKey: .parentIndex)
        try container.encodeIfPresent(index, forKey: .index)
        try container.encodeIfPresent(posterFileName, forKey: .posterFileName)
        try container.encode(videoFileName, forKey: .videoFileName)
        try container.encodeIfPresent(fileSize, forKey: .fileSize)
        try container.encode(requestedQuality, forKey: .requestedQuality)
        try container.encode(effectiveQuality, forKey: .effectiveQuality)
        try container.encodeIfPresent(audioTitle, forKey: .audioTitle)
        try container.encodeIfPresent(subtitleTitle, forKey: .subtitleTitle)
        try container.encodeIfPresent(subtitleFileName, forKey: .subtitleFileName)
        try container.encodeIfPresent(subtitleLanguage, forKey: .subtitleLanguage)
        try container.encodeIfPresent(subtitleCodec, forKey: .subtitleCodec)
        try container.encode(subtitleIsForced, forKey: .subtitleIsForced)
        try container.encode(createdAt, forKey: .createdAt)
    }

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
        case .series:
            return nil
        case .collection, .playlist, .folder, .unknown:
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
    var remoteReference: MediaDownloadRemoteReference?
    var trackPreference: MediaDownloadTrackPreference?
    var errorMessage: String?
    var metadata: DownloadedMediaMetadata

    var identity: MediaIdentity? {
        metadata.identity
    }

    var itemID: String {
        metadata.itemID
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
