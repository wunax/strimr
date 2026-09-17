import Foundation

private extension KeyedDecodingContainer {
    nonisolated func decodeJellyfinStringIfPresent(forKey key: Key) -> String? {
        if let value = try? decode(String.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return String(value)
        }
        if let value = try? decode(Double.self, forKey: key) {
            return String(value)
        }
        return nil
    }

    nonisolated func decodeJellyfinIntIfPresent(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int(value)
        }
        return nil
    }

    nonisolated func decodeJellyfinInt64IfPresent(forKey key: Key) -> Int64? {
        if let value = try? decode(Int64.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Int64(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let value = try? decode(Double.self, forKey: key), value.isFinite {
            return Int64(value)
        }
        return nil
    }

    nonisolated func decodeJellyfinDoubleIfPresent(forKey key: Key) -> Double? {
        if let value = try? decode(Double.self, forKey: key) {
            return value
        }
        if let value = try? decode(String.self, forKey: key) {
            return Double(value.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return nil
    }

    nonisolated func decodeJellyfinBoolIfPresent(forKey key: Key) -> Bool? {
        if let value = try? decode(Bool.self, forKey: key) {
            return value
        }
        if let value = try? decode(Int.self, forKey: key) {
            return value != 0
        }
        if let value = try? decode(String.self, forKey: key) {
            switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
            case "true", "yes", "y", "on", "1":
                return true
            case "false", "no", "n", "off", "0", "":
                return false
            default:
                return nil
            }
        }
        return nil
    }
}

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
    let configuration: JellyfinUserConfiguration?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case serverID = "ServerId"
        case policy = "Policy"
        case configuration = "Configuration"
    }
}

nonisolated struct JellyfinUserConfiguration: Codable, Hashable, Sendable {
    let audioLanguagePreference: String?
    let castReceiverID: String?
    let displayCollectionsView: Bool?
    let displayMissingEpisodes: Bool?
    let enableLocalPassword: Bool?
    let enableNextEpisodeAutoPlay: Bool?
    let groupedFolders: [String]?
    let hidePlayedInLatest: Bool?
    let latestItemsExcludes: [String]?
    let myMediaExcludes: [String]?
    let orderedViews: [String]?
    let playDefaultAudioTrack: Bool?
    let rememberAudioSelections: Bool?
    let rememberSubtitleSelections: Bool?
    let subtitleLanguagePreference: String?
    let subtitleMode: String?

    private enum CodingKeys: String, CodingKey {
        case audioLanguagePreference = "AudioLanguagePreference"
        case castReceiverID = "CastReceiverId"
        case displayCollectionsView = "DisplayCollectionsView"
        case displayMissingEpisodes = "DisplayMissingEpisodes"
        case enableLocalPassword = "EnableLocalPassword"
        case enableNextEpisodeAutoPlay = "EnableNextEpisodeAutoPlay"
        case groupedFolders = "GroupedFolders"
        case hidePlayedInLatest = "HidePlayedInLatest"
        case latestItemsExcludes = "LatestItemsExcludes"
        case myMediaExcludes = "MyMediaExcludes"
        case orderedViews = "OrderedViews"
        case playDefaultAudioTrack = "PlayDefaultAudioTrack"
        case rememberAudioSelections = "RememberAudioSelections"
        case rememberSubtitleSelections = "RememberSubtitleSelections"
        case subtitleLanguagePreference = "SubtitleLanguagePreference"
        case subtitleMode = "SubtitleMode"
    }
}

nonisolated struct JellyfinUserPolicy: Codable, Hashable, Sendable {
    let isAdministrator: Bool?
    let enableMediaPlayback: Bool?
    let enableContentDownloading: Bool?
    let enableSubtitleManagement: Bool?
    let enableLiveTVAccess: Bool?
    let enableLiveTVManagement: Bool?
    let enableContentDeletion: Bool?

    private enum CodingKeys: String, CodingKey {
        case isAdministrator = "IsAdministrator"
        case enableMediaPlayback = "EnableMediaPlayback"
        case enableContentDownloading = "EnableContentDownloading"
        case enableSubtitleManagement = "EnableSubtitleManagement"
        case enableLiveTVAccess = "EnableLiveTvAccess"
        case enableLiveTVManagement = "EnableLiveTvManagement"
        case enableContentDeletion = "EnableContentDeletion"
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

nonisolated struct JellyfinNameIDPair: Decodable, Sendable {
    let name: String
    let id: String

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case id = "Id"
    }
}

nonisolated struct JellyfinQueryFilters: Decodable, Sendable {
    let genres: [JellyfinNameIDPair]

    private enum CodingKeys: String, CodingKey {
        case genres = "Genres"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        genres = try container.decodeIfPresent([JellyfinNameIDPair].self, forKey: .genres) ?? []
    }
}

nonisolated struct JellyfinLegacyQueryFilters: Decodable, Sendable {
    let years: [Int]

    private enum CodingKeys: String, CodingKey {
        case years = "Years"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        years = try container.decodeIfPresent([Int].self, forKey: .years) ?? []
    }
}

nonisolated struct JellyfinRecommendation: Decodable, Sendable {
    let items: [JellyfinItem]
    let recommendationType: String?
    let baselineItemName: String?
    let categoryID: String?

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
        case recommendationType = "RecommendationType"
        case baselineItemName = "BaselineItemName"
        case categoryID = "CategoryId"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([JellyfinItem].self, forKey: .items) ?? []
        recommendationType = try container.decodeIfPresent(String.self, forKey: .recommendationType)
        baselineItemName = try container.decodeIfPresent(String.self, forKey: .baselineItemName)
        categoryID = try container.decodeIfPresent(String.self, forKey: .categoryID)
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
    let criticRating: Double?
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
    let trickplay: [String: [String: JellyfinTrickplayInfo]]?
    let canDownload: Bool?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case type = "Type"
        case collectionType = "CollectionType"
        case overview = "Overview"
        case runTimeTicks = "RunTimeTicks"
        case productionYear = "ProductionYear"
        case communityRating = "CommunityRating"
        case criticRating = "CriticRating"
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
        case trickplay = "Trickplay"
        case canDownload = "CanDownload"
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
        case "video", "trailer": .clip
        case "boxset": .collection
        case "playlist": .playlist
        case "folder", "collectionfolder": .folder
        default: .unknown
        }
    }

    var isPlayable: Bool {
        kind == .movie || kind == .episode || kind == .clip
    }

    var duration: TimeInterval? {
        runTimeTicks.map(JellyfinTime.seconds(fromTicks:))
    }

    var resumePosition: TimeInterval? {
        guard let ticks = userData?.playbackPositionTicks, ticks > 0 else {
            return nil
        }

        return JellyfinTime.seconds(fromTicks: ticks)
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
        case .series, .season, .clip, .collection, .playlist, .folder, .unknown:
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

nonisolated struct JellyfinTrickplayInfo: Decodable, Hashable, Sendable {
    let width: Int
    let height: Int
    let tileWidth: Int
    let tileHeight: Int
    let thumbnailCount: Int
    let interval: Int

    private enum CodingKeys: String, CodingKey {
        case width = "Width"
        case height = "Height"
        case tileWidth = "TileWidth"
        case tileHeight = "TileHeight"
        case thumbnailCount = "ThumbnailCount"
        case interval = "Interval"
    }
}

nonisolated struct JellyfinMediaSegmentsResponse: Decodable, Sendable {
    let items: [JellyfinMediaSegment]

    private enum CodingKeys: String, CodingKey {
        case items = "Items"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([JellyfinMediaSegment].self, forKey: .items) ?? []
    }
}

nonisolated struct JellyfinMediaSegment: Decodable, Sendable {
    let id: String?
    let type: String
    let startTicks: Int64
    let endTicks: Int64

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case type = "Type"
        case startTicks = "StartTicks"
        case endTicks = "EndTicks"
    }
}

nonisolated struct JellyfinRemoteSubtitle: Decodable, Sendable {
    let id: String
    let name: String?
    let providerName: String?
    let format: String?
    let threeLetterISOLanguageName: String?
    let isForced: Bool?
    let hearingImpaired: Bool?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case providerName = "ProviderName"
        case format = "Format"
        case threeLetterISOLanguageName = "ThreeLetterISOLanguageName"
        case isForced = "IsForced"
        case hearingImpaired = "HearingImpaired"
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
    let unplayedItemCount: Int?
    let isFavorite: Bool?

    private enum CodingKeys: String, CodingKey {
        case played = "Played"
        case playbackPositionTicks = "PlaybackPositionTicks"
        case playCount = "PlayCount"
        case unplayedItemCount = "UnplayedItemCount"
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
    let imagePath: String?
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
        case imagePath = "ImagePath"
        case imageTag = "ImageTag"
    }
}

nonisolated struct JellyfinMediaSource: Decodable, Hashable, Sendable {
    let id: String
    let name: String?
    let path: String?
    let container: String?
    let runTimeTicks: Int64?
    let size: Int64?
    let type: String?
    let protocolName: String?
    let videoType: String?
    let isRemote: Bool?
    let isInfiniteStream: Bool?
    let eTag: String?
    let timestamp: String?
    let supportsDirectPlay: Bool?
    let supportsDirectStream: Bool?
    let supportsTranscoding: Bool?
    let transcodingURL: String?
    let liveStreamID: String?
    let requiredHTTPHeaders: [String: String]?
    let bitrate: Int?
    let defaultAudioStreamIndex: Int?
    let defaultSubtitleStreamIndex: Int?
    let mediaStreams: [JellyfinMediaStream]?
    let mediaAttachments: [JellyfinMediaAttachment]?

    private enum CodingKeys: String, CodingKey {
        case id = "Id"
        case name = "Name"
        case path = "Path"
        case container = "Container"
        case runTimeTicks = "RunTimeTicks"
        case size = "Size"
        case type = "Type"
        case protocolName = "Protocol"
        case videoType = "VideoType"
        case isRemote = "IsRemote"
        case isInfiniteStream = "IsInfiniteStream"
        case eTag = "ETag"
        case timestamp = "Timestamp"
        case supportsDirectPlay = "SupportsDirectPlay"
        case supportsDirectStream = "SupportsDirectStream"
        case supportsTranscoding = "SupportsTranscoding"
        case transcodingURL = "TranscodingUrl"
        case liveStreamID = "LiveStreamId"
        case requiredHTTPHeaders = "RequiredHttpHeaders"
        case bitrate = "Bitrate"
        case defaultAudioStreamIndex = "DefaultAudioStreamIndex"
        case defaultSubtitleStreamIndex = "DefaultSubtitleStreamIndex"
        case mediaStreams = "MediaStreams"
        case mediaAttachments = "MediaAttachments"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = container.decodeJellyfinStringIfPresent(forKey: .name)
        path = container.decodeJellyfinStringIfPresent(forKey: .path)
        self.container = container.decodeJellyfinStringIfPresent(forKey: .container)
        runTimeTicks = container.decodeJellyfinInt64IfPresent(forKey: .runTimeTicks)
        size = container.decodeJellyfinInt64IfPresent(forKey: .size)
        type = container.decodeJellyfinStringIfPresent(forKey: .type)
        protocolName = container.decodeJellyfinStringIfPresent(forKey: .protocolName)
        videoType = container.decodeJellyfinStringIfPresent(forKey: .videoType)
        isRemote = container.decodeJellyfinBoolIfPresent(forKey: .isRemote)
        isInfiniteStream = container.decodeJellyfinBoolIfPresent(forKey: .isInfiniteStream)
        eTag = container.decodeJellyfinStringIfPresent(forKey: .eTag)
        timestamp = container.decodeJellyfinStringIfPresent(forKey: .timestamp)
        supportsDirectPlay = container.decodeJellyfinBoolIfPresent(forKey: .supportsDirectPlay)
        supportsDirectStream = container.decodeJellyfinBoolIfPresent(forKey: .supportsDirectStream)
        supportsTranscoding = container.decodeJellyfinBoolIfPresent(forKey: .supportsTranscoding)
        transcodingURL = container.decodeJellyfinStringIfPresent(forKey: .transcodingURL)
        liveStreamID = container.decodeJellyfinStringIfPresent(forKey: .liveStreamID)
        requiredHTTPHeaders = try? container.decodeIfPresent([String: String].self, forKey: .requiredHTTPHeaders)
        bitrate = container.decodeJellyfinIntIfPresent(forKey: .bitrate)
        defaultAudioStreamIndex = container.decodeJellyfinIntIfPresent(forKey: .defaultAudioStreamIndex)
        defaultSubtitleStreamIndex = container.decodeJellyfinIntIfPresent(forKey: .defaultSubtitleStreamIndex)
        mediaStreams = try? container.decodeIfPresent([JellyfinMediaStream].self, forKey: .mediaStreams)
        mediaAttachments = try? container.decodeIfPresent([JellyfinMediaAttachment].self, forKey: .mediaAttachments)
    }
}

nonisolated struct JellyfinMediaStream: Decodable, Hashable, Sendable {
    let index: Int
    let type: String
    let codec: String?
    let title: String?
    let displayTitle: String?
    let language: String?
    let isDefault: Bool?
    let isForced: Bool?
    let isHearingImpaired: Bool?
    let isExternal: Bool?
    let deliveryMethod: String?
    let deliveryURL: String?
    let bitrate: Int?
    let profile: String?
    let level: Double?
    let codecTag: String?
    let realFrameRate: Double?
    let averageFrameRate: Double?
    let isInterlaced: Bool?
    let bitDepth: Int?
    let refFrames: Int?
    let pixelFormat: String?
    let colorSpace: String?
    let colorRange: String?
    let colorPrimaries: String?
    let colorTransfer: String?
    let aspectRatio: String?
    let isAnamorphic: Bool?
    let videoRange: String?
    let videoRangeType: String?
    let hdr10PlusPresent: Bool?
    let dolbyVisionProfile: Int?
    let dolbyVisionLevel: Int?
    let dolbyVisionVersion: String?
    let dolbyVisionCompatibilityID: Int?
    let dolbyVisionTitle: String?
    let channels: Int?
    let channelLayout: String?
    let sampleRate: Int?
    let spatialFormat: String?
    let subtitleFormat: String?
    let path: String?
    let timeBase: String?
    let rotation: Int?
    let isTextSubtitle: Bool?
    let supportsExternalStream: Bool?
    let comment: String?
    let width: Int?
    let height: Int?

    private enum CodingKeys: String, CodingKey {
        case index = "Index"
        case type = "Type"
        case codec = "Codec"
        case title = "Title"
        case displayTitle = "DisplayTitle"
        case language = "Language"
        case isDefault = "IsDefault"
        case isForced = "IsForced"
        case isHearingImpaired = "IsHearingImpaired"
        case isExternal = "IsExternal"
        case deliveryMethod = "DeliveryMethod"
        case deliveryURL = "DeliveryUrl"
        case bitrate = "BitRate"
        case profile = "Profile"
        case level = "Level"
        case codecTag = "CodecTag"
        case realFrameRate = "RealFrameRate"
        case averageFrameRate = "AverageFrameRate"
        case isInterlaced = "IsInterlaced"
        case bitDepth = "BitDepth"
        case refFrames = "RefFrames"
        case pixelFormat = "PixelFormat"
        case colorSpace = "ColorSpace"
        case colorRange = "ColorRange"
        case colorPrimaries = "ColorPrimaries"
        case colorTransfer = "ColorTransfer"
        case aspectRatio = "AspectRatio"
        case isAnamorphic = "IsAnamorphic"
        case videoRange = "VideoRange"
        case videoRangeType = "VideoRangeType"
        case hdr10PlusPresent = "Hdr10PlusPresentFlag"
        case legacyHdr10PlusPresent = "Hdr10PlusPresent"
        case dolbyVisionProfile = "DvProfile"
        case legacyDolbyVisionProfile = "DoviProfile"
        case dolbyVisionLevel = "DvLevel"
        case legacyDolbyVisionLevel = "DoviLevel"
        case dolbyVisionVersion = "DoviVersion"
        case dolbyVisionVersionMajor = "DvVersionMajor"
        case dolbyVisionVersionMinor = "DvVersionMinor"
        case dolbyVisionCompatibilityID = "DvBlSignalCompatibilityId"
        case legacyDolbyVisionCompatibilityID = "DOVIBLCompatID"
        case dolbyVisionTitle = "VideoDoViTitle"
        case channels = "Channels"
        case channelLayout = "ChannelLayout"
        case sampleRate = "SampleRate"
        case spatialFormat = "AudioSpatialFormat"
        case legacySpatialFormat = "SpatialFormat"
        case subtitleFormat = "SubtitleFormat"
        case path = "Path"
        case timeBase = "TimeBase"
        case rotation = "Rotation"
        case isTextSubtitle = "IsTextSubtitle"
        case supportsExternalStream = "SupportsExternalStream"
        case comment = "Comment"
        case width = "Width"
        case height = "Height"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        index = container.decodeJellyfinIntIfPresent(forKey: .index) ?? -1
        type = Self.normalizedMediaStreamType(container.decodeJellyfinStringIfPresent(forKey: .type)) ?? "unknown"
        codec = container.decodeJellyfinStringIfPresent(forKey: .codec)
        title = container.decodeJellyfinStringIfPresent(forKey: .title)
        displayTitle = container.decodeJellyfinStringIfPresent(forKey: .displayTitle)
        language = container.decodeJellyfinStringIfPresent(forKey: .language)
        isDefault = container.decodeJellyfinBoolIfPresent(forKey: .isDefault)
        isForced = container.decodeJellyfinBoolIfPresent(forKey: .isForced)
        isHearingImpaired = container.decodeJellyfinBoolIfPresent(forKey: .isHearingImpaired)
        isExternal = container.decodeJellyfinBoolIfPresent(forKey: .isExternal)
        deliveryMethod = container.decodeJellyfinStringIfPresent(forKey: .deliveryMethod)
        deliveryURL = container.decodeJellyfinStringIfPresent(forKey: .deliveryURL)
        bitrate = container.decodeJellyfinIntIfPresent(forKey: .bitrate)
        profile = container.decodeJellyfinStringIfPresent(forKey: .profile)
        level = container.decodeJellyfinDoubleIfPresent(forKey: .level)
        codecTag = container.decodeJellyfinStringIfPresent(forKey: .codecTag)
        realFrameRate = container.decodeJellyfinDoubleIfPresent(forKey: .realFrameRate)
        averageFrameRate = container.decodeJellyfinDoubleIfPresent(forKey: .averageFrameRate)
        isInterlaced = container.decodeJellyfinBoolIfPresent(forKey: .isInterlaced)
        bitDepth = container.decodeJellyfinIntIfPresent(forKey: .bitDepth)
        refFrames = container.decodeJellyfinIntIfPresent(forKey: .refFrames)
        pixelFormat = container.decodeJellyfinStringIfPresent(forKey: .pixelFormat)
        colorSpace = container.decodeJellyfinStringIfPresent(forKey: .colorSpace)
        colorRange = container.decodeJellyfinStringIfPresent(forKey: .colorRange)
        colorPrimaries = container.decodeJellyfinStringIfPresent(forKey: .colorPrimaries)
        colorTransfer = container.decodeJellyfinStringIfPresent(forKey: .colorTransfer)
        aspectRatio = container.decodeJellyfinStringIfPresent(forKey: .aspectRatio)
        isAnamorphic = container.decodeJellyfinBoolIfPresent(forKey: .isAnamorphic)
        videoRange = container.decodeJellyfinStringIfPresent(forKey: .videoRange)
        videoRangeType = container.decodeJellyfinStringIfPresent(forKey: .videoRangeType)
        hdr10PlusPresent = container.decodeJellyfinBoolIfPresent(forKey: .hdr10PlusPresent)
            ?? container.decodeJellyfinBoolIfPresent(forKey: .legacyHdr10PlusPresent)

        dolbyVisionProfile = container.decodeJellyfinIntIfPresent(forKey: .dolbyVisionProfile)
            ?? container.decodeJellyfinIntIfPresent(forKey: .legacyDolbyVisionProfile)
        dolbyVisionLevel = container.decodeJellyfinIntIfPresent(forKey: .dolbyVisionLevel)
            ?? container.decodeJellyfinIntIfPresent(forKey: .legacyDolbyVisionLevel)
        let versionMajor = container.decodeJellyfinIntIfPresent(forKey: .dolbyVisionVersionMajor)
        let versionMinor = container.decodeJellyfinIntIfPresent(forKey: .dolbyVisionVersionMinor)
        dolbyVisionVersion = container.decodeJellyfinStringIfPresent(forKey: .dolbyVisionVersion)
            ?? Self.dolbyVisionVersion(major: versionMajor, minor: versionMinor)
        dolbyVisionCompatibilityID = container.decodeJellyfinIntIfPresent(forKey: .dolbyVisionCompatibilityID)
            ?? container.decodeJellyfinIntIfPresent(forKey: .legacyDolbyVisionCompatibilityID)
        dolbyVisionTitle = container.decodeJellyfinStringIfPresent(forKey: .dolbyVisionTitle)

        channels = container.decodeJellyfinIntIfPresent(forKey: .channels)
        channelLayout = container.decodeJellyfinStringIfPresent(forKey: .channelLayout)
        sampleRate = container.decodeJellyfinIntIfPresent(forKey: .sampleRate)
        let rawSpatialFormat = container.decodeJellyfinStringIfPresent(forKey: .spatialFormat)
            ?? container.decodeJellyfinStringIfPresent(forKey: .legacySpatialFormat)
        spatialFormat = Self.normalizedSpatialFormat(rawSpatialFormat)
        subtitleFormat = container.decodeJellyfinStringIfPresent(forKey: .subtitleFormat)
        path = container.decodeJellyfinStringIfPresent(forKey: .path)
        timeBase = container.decodeJellyfinStringIfPresent(forKey: .timeBase)
        rotation = container.decodeJellyfinIntIfPresent(forKey: .rotation)
        isTextSubtitle = container.decodeJellyfinBoolIfPresent(forKey: .isTextSubtitle)
        supportsExternalStream = container.decodeJellyfinBoolIfPresent(forKey: .supportsExternalStream)
        comment = container.decodeJellyfinStringIfPresent(forKey: .comment)
        width = container.decodeJellyfinIntIfPresent(forKey: .width)
        height = container.decodeJellyfinIntIfPresent(forKey: .height)
    }

    private static func normalizedMediaStreamType(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0":
            "audio"
        case "1":
            "video"
        case "2":
            "subtitle"
        default:
            value
        }
    }

    private static func normalizedSpatialFormat(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return switch value.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "0", "none":
            nil
        case "1", "dolbyatmos", "dolby atmos", "atmos":
            "Atmos"
        case "2", "dtsx", "dts:x":
            "DTS:X"
        default:
            value
        }
    }

    private static func dolbyVisionVersion(major: Int?, minor: Int?) -> String? {
        return switch (major, minor) {
        case let (major?, minor?):
            "\(major).\(minor)"
        case let (major?, nil):
            String(major)
        case let (nil, minor?):
            String(minor)
        default:
            nil
        }
    }
}

nonisolated struct JellyfinMediaAttachment: Decodable, Hashable, Sendable {
    let index: Int?
    let fileName: String?
    let mimeType: String?
    let codec: String?
    let codecTag: String?

    private enum CodingKeys: String, CodingKey {
        case index = "Index"
        case fileName = "FileName"
        case mimeType = "MimeType"
        case codec = "Codec"
        case codecTag = "CodecTag"
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
