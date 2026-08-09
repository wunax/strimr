import Foundation

nonisolated struct JellyfinPublicSystemInfo: Decodable, Hashable, Sendable {
    let id: String
    let serverName: String
    let version: String
    let productName: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case serverName = "ServerName"
        case version = "Version"
        case productName = "ProductName"
    }
}

nonisolated struct JellyfinAuthenticatedSession: Decodable, Sendable {
    let user: JellyfinUser
    let accessToken: String
    let serverID: String

    private enum CodingKeys: String, CodingKey {
        case user = "User"
        case accessToken = "AccessToken"
        case serverID = "ServerId"
    }
}

nonisolated struct JellyfinUser: Codable, Hashable, Sendable {
    let id: String
    let name: String
    let serverID: String?
    let policy: JellyfinUserPolicy?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverID = "ServerId"
        case policy = "Policy"
    }
}

nonisolated struct JellyfinUserPolicy: Codable, Hashable, Sendable {
    let isAdministrator: Bool?
    let enableMediaPlayback: Bool?
    let enableContentDownloading: Bool?

    private enum CodingKeys: String, CodingKey {
        case isAdministrator = "IsAdministrator"
        case enableMediaPlayback = "EnableMediaPlayback"
        case enableContentDownloading = "EnableContentDownloading"
    }
}

nonisolated struct JellyfinConnection: Codable, Hashable, Sendable {
    let baseURL: URL
    let serverID: String
    let serverName: String
    let serverVersion: String
    let userID: String
    let username: String

    var serverIdentity: ServerIdentity {
        ServerIdentity(provider: .jellyfin, id: serverID)
    }
}

nonisolated struct JellyfinQueryResult<Element: Decodable & Sendable>: Decodable, Sendable {
    let items: [Element]
    let startIndex: Int?
    let totalRecordCount: Int?

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
        case startIndex = "StartIndex"
        case totalRecordCount = "TotalRecordCount"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([Element].self, forKey: .items) ?? []
        startIndex = try container.decodeIfPresent(Int.self, forKey: .startIndex)
        totalRecordCount = try container.decodeIfPresent(Int.self, forKey: .totalRecordCount)
    }
}

nonisolated struct JellyfinItem: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let type: String?
    let collectionType: String?
    let overview: String?
    let runTimeTicks: Int64?
    let productionYear: Int?
    let communityRating: Double?
    let officialRating: String?
    let genres: [String]?
    let studios: [JellyfinStudio]?
    let providerIDs: [String: String]?
    let taglines: [String]?
    let parentID: String?
    let seriesID: String?
    let seasonID: String?
    let seriesName: String?
    let seasonName: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let childCount: Int?
    let recursiveItemCount: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let parentThumbItemID: String?
    let seriesPrimaryImageTag: String?
    let seriesThumbImageTag: String?
    let userData: JellyfinUserData?
    let people: [JellyfinPerson]?
    let mediaSources: [JellyfinMediaSource]?
    let chapters: [JellyfinChapter]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case overview = "Overview"
        case runTimeTicks = "RunTimeTicks"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case officialRating = "OfficialRating"
        case genres = "Genres"
        case studios = "Studios"
        case providerIDs = "ProviderIds"
        case taglines = "Taglines"
        case parentID = "ParentId"
        case seriesID = "SeriesId"
        case seasonID = "SeasonId"
        case seriesName = "SeriesName"
        case seasonName = "SeasonName"
        case parentIndexNumber = "ParentIndexNumber"
        case indexNumber = "IndexNumber"
        case childCount = "ChildCount"
        case recursiveItemCount = "RecursiveItemCount"
        case imageTags = "ImageTags"
        case backdropImageTags = "BackdropImageTags"
        case parentThumbItemID = "ParentThumbItemId"
        case seriesPrimaryImageTag = "SeriesPrimaryImageTag"
        case seriesThumbImageTag = "SeriesThumbImageTag"
        case userData = "UserData"
        case people = "People"
        case mediaSources = "MediaSources"
        case chapters = "Chapters"
    }

    static func == (lhs: JellyfinItem, rhs: JellyfinItem) -> Bool {
        lhs.id == rhs.id
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(id)
    }

    var kind: MediaKind {
        switch type?.lowercased() {
        case "movie": .movie
        case "series": .series
        case "season": .season
        case "episode": .episode
        case "boxset": .collection
        case "playlist": .playlist
        case "folder", "collectionfolder": .folder
        default: .unknown
        }
    }

    var isPlayable: Bool {
        kind == .movie || kind == .episode
    }

    var duration: TimeInterval? {
        runTimeTicks.map(JellyfinTime.seconds(fromTicks:))
    }

    var resumePosition: TimeInterval? {
        userData?.playbackPositionTicks.map(JellyfinTime.seconds(fromTicks:))
    }

    var primaryLabel: String {
        seriesName ?? name
    }

    var secondaryLabel: String? {
        switch kind {
        case .movie:
            productionYear.map(String.init)
        case .episode:
            name
        case .series, .season, .collection, .playlist, .folder, .unknown:
            nil
        }
    }

    var tertiaryLabel: String? {
        guard kind == .episode, let parentIndexNumber, let indexNumber else { return nil }
        return String(localized: "media.labels.seasonEpisode \(parentIndexNumber) \(indexNumber)")
    }

    var progress: Double? {
        guard let duration, duration > 0, let resumePosition else { return nil }
        return min(1, max(0, resumePosition / duration))
    }
}

nonisolated struct JellyfinStudio: Decodable, Hashable, Sendable {
    let name: String

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
    }
}

nonisolated struct JellyfinUserData: Decodable, Hashable, Sendable {
    let played: Bool?
    let playbackPositionTicks: Int64?
    let playCount: Int?
    let isFavorite: Bool?

    private enum CodingKeys: String, CodingKey {
        case played = "Played"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case isFavorite = "IsFavorite"
    }
}

nonisolated struct JellyfinPerson: Decodable, Identifiable, Hashable, Sendable {
    let id: String
    let name: String
    let role: String?
    let type: String?
    let primaryImageTag: String?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case role = "Role"
        case type = "Type"
        case primaryImageTag = "PrimaryImageTag"
    }
}

nonisolated struct JellyfinChapter: Decodable, Identifiable, Hashable, Sendable {
    let name: String?
    let startPositionTicks: Int64
    let imageTag: String?

    var id: Int64 {
        startPositionTicks
    }

    var startTime: TimeInterval {
        JellyfinTime.seconds(fromTicks: startPositionTicks)
    }

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case startPositionTicks = "StartPositionTicks"
        case imageTag = "ImageTag"
    }
}

nonisolated struct JellyfinMediaSource: Decodable, Hashable, Sendable {
    let id: String
    let name: String?
    let container: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let transcodingURL: String?
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
    let mediaStreams: [JellyfinMediaStream]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case container = "Container"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingURL = "TranscodingUrl"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
        case mediaStreams = "MediaStreams"
    }
}

nonisolated struct JellyfinMediaStream: Decodable, Hashable, Sendable {
    let index: Int
    let type: String
    let codec: String?
    let displayTitle: String?
    let language: String?
    let isDefault: Bool?
    let isForced: Bool?
    let isExternal: Bool?
    let deliveryMethod: String?
    let deliveryURL: String?

    private enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case displayTitle = "DisplayTitle"
        case language = "Language"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isExternal = "IsExternal"
        case deliveryMethod = "DeliveryMethod"
        case deliveryURL = "DeliveryUrl"
    }
}

nonisolated struct JellyfinPlaybackInfo: Decodable, Sendable {
    let playSessionID: String?
    let errorCode: String?
    let mediaSources: [JellyfinMediaSource]?

    private enum CodingKeys: String, CodingKey {
        case playSessionID = "PlaySessionId"
        case errorCode = "ErrorCode"
        case mediaSources = "MediaSources"
    }
}

nonisolated enum JellyfinTime {
    static let ticksPerSecond: Int64 = 10_000_000

    static func seconds(fromTicks ticks: Int64) -> TimeInterval {
        TimeInterval(max(0, ticks)) / TimeInterval(ticksPerSecond)
    }

    static func ticks(fromSeconds seconds: TimeInterval) -> Int64 {
        guard seconds.isFinite, seconds > 0 else { return 0 }
        let scaled = seconds * TimeInterval(ticksPerSecond)
        return scaled >= TimeInterval(Int64.max) ? Int64.max : Int64(scaled.rounded())
    }
}
