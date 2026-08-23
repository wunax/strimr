import Foundation

final class DownloadQueueRepository {
    struct QueueItemStatus {
        let status: String
        let progress: Double?
        let hasError: Bool
    }

    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        self.context = context
        network = PlexServerNetworkClient(context: context)
    }

    func createQueue() async throws -> Int {
        let response: QueueResponse = try await network.request(
            path: "/downloadQueue",
            method: "POST",
            headers: apiHeaders,
        )
        guard let id = response.mediaContainer.queues?.first?.id else {
            throw PlexAPIError.invalidResponse
        }
        return id
    }

    func add(
        ratingKey: String,
        queueID: Int,
        quality: TranscodeQualityPreset,
    ) async throws -> Int {
        guard let bitrate = quality.maximumVideoBitrateKbps else {
            throw PlexAPIError.invalidResponse
        }
        let sessionID = UUID().uuidString.lowercased()
        let profile = [
            "add-transcode-target(type=videoProfile&context=all&protocol=http&container=mkv&videoCodec=h264,hevc&audioCodec=aac,ac3,eac3,opus,mp3,flac&subtitleCodec=ass,mov_text,pgs,srt,ssa,text,vobsub,webvtt)",
            "add-transcode-target-settings(type=videoProfile&context=all&protocol=http&CopyMatroskaAttachments=true)",
            "add-settings(DirectPlayStreamSelection=true)",
        ].joined(separator: "+")
        let path = "/library/metadata/\(ratingKey)"
        let query = [
            URLQueryItem(name: "keys", value: path),
            URLQueryItem(name: "path", value: path),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "protocol", value: "http"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "session", value: sessionID),
            URLQueryItem(name: "mediaIndex", value: "0"),
            URLQueryItem(name: "partIndex", value: "0"),
            URLQueryItem(name: "mediaBufferSize", value: "50000"),
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "subtitleSize", value: "0"),
            URLQueryItem(name: "videoQuality", value: String(quality.downloadQueueVideoQuality)),
            URLQueryItem(name: "videoResolution", value: quality.downloadQueueResolution),
            URLQueryItem(name: "maxVideoBitrate", value: String(bitrate)),
            URLQueryItem(name: "audioBoost", value: "0"),
            URLQueryItem(name: "autoAdjustSubtitle", value: "0"),
            URLQueryItem(name: "advancedSubtitles", value: "text"),
            URLQueryItem(name: "copyts", value: "1"),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: profile),
            URLQueryItem(name: "X-Plex-Client-Profile-Name", value: "Generic"),
        ]
        let response: AddResponse = try await network.request(
            path: "/downloadQueue/\(queueID)/add",
            queryItems: query,
            method: "POST",
            headers: apiHeaders,
        )
        guard let id = response.mediaContainer.items?.first?.id else {
            throw PlexAPIError.invalidResponse
        }
        return id
    }

    func status(queueID: Int, itemID: Int) async throws -> QueueItemStatus {
        let response: ItemsResponse = try await network.request(
            path: "/downloadQueue/\(queueID)/items",
            headers: apiHeaders,
        )
        guard let item = response.mediaContainer.items?.first(where: { $0.id == itemID }) else {
            throw PlexAPIError.invalidResponse
        }
        return QueueItemStatus(
            status: item.status.lowercased(),
            progress: item.transcodeSession?.progress.map { min(max($0 / 100, 0), 1) },
            hasError: item.transcodeSession?.error == true,
        )
    }

    func mediaRequest(queueID: Int, itemID: Int) throws -> URLRequest {
        guard let context,
              let url = try MediaRepository(context: context).mediaURL(
                  path: "/downloadQueue/\(queueID)/item/\(itemID)/media",
              )
        else { throw PlexAPIError.invalidURL }
        return URLRequest(url: url)
    }

    func delete(queueID: Int, itemID: Int) async throws {
        try await network.send(
            path: "/downloadQueue/\(queueID)/items/\(itemID)",
            method: "DELETE",
            headers: apiHeaders,
        )
    }

    private var apiHeaders: [String: String] {
        ["Accept": "application/json", "X-Plex-Pms-Api-Version": "1.0.0"]
    }
}

private extension TranscodeQualityPreset {
    var downloadQueueResolution: String {
        switch self {
        case .original: "1920x1080"
        case .p240_320: "420x240"
        case .p360_700: "640x360"
        case .p480_1_5mbps: "720x480"
        case .p720_2mbps, .p720_4mbps: "1280x720"
        case .p1080_8mbps, .p1080_12mbps: "1920x1080"
        }
    }

    var downloadQueueVideoQuality: Int {
        switch self {
        case .original: 100
        case .p240_320: 30
        case .p360_700: 40
        case .p480_1_5mbps, .p720_2mbps, .p1080_8mbps: 60
        case .p1080_12mbps: 90
        case .p720_4mbps: 100
        }
    }
}

private struct QueueResponse: Decodable {
    let mediaContainer: Container
    struct Container: Decodable {
        let queues: [Queue]?
        struct Queue: Decodable { let id: Int }
        private enum CodingKeys: String, CodingKey { case queues = "DownloadQueue" }
    }

    private enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct AddResponse: Decodable {
    let mediaContainer: Container
    struct Container: Decodable {
        let items: [Item]?
        struct Item: Decodable { let id: Int }
        private enum CodingKeys: String, CodingKey {
            case addedQueueItems = "AddedQueueItems"
            case downloadQueueItems = "DownloadQueueItem"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            items = try container.decodeIfPresent([Item].self, forKey: .addedQueueItems)
                ?? container.decodeIfPresent([Item].self, forKey: .downloadQueueItems)
        }
    }

    private enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct ItemsResponse: Decodable {
    let mediaContainer: Container
    struct Container: Decodable {
        let items: [Item]?
        struct Item: Decodable {
            let id: Int
            let status: String
            let transcodeSession: Session?
            struct Session: Decodable {
                let progress: Double?
                let error: Bool?
            }

            private enum CodingKeys: String, CodingKey {
                case id
                case status
                case transcodeSession = "TranscodeSession"
            }
        }

        private enum CodingKeys: String, CodingKey { case items = "DownloadQueueItem" }
    }

    private enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}
