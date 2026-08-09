import AetherEngine
import Foundation

struct JellyfinPlaybackPlan: Sendable {
    let item: JellyfinItem
    let url: URL
    let headers: [String: String]
    let mediaSourceID: String
    let playSessionID: String
    let initialPosition: TimeInterval?
    let preferredAudioStreamIndex: Int?
    let preferredSubtitleStreamIndex: Int?
    let chapters: [JellyfinChapter]
    let externalSubtitles: [ExternalSubtitleTrack]
}

@MainActor
struct JellyfinPlaybackService {
    private let context: JellyfinAPIContext

    init(context: JellyfinAPIContext) {
        self.context = context
    }

    func prepare(item: JellyfinItem, resume: Bool = true) async throws -> JellyfinPlaybackPlan {
        guard let userID = context.connection?.userID else {
            throw JellyfinAPIError.authenticationRequired
        }

        let body = JellyfinPlaybackInfoRequest(
            userID: userID,
            startTimeTicks: resume ? (item.userData?.playbackPositionTicks ?? 0) : 0,
            deviceProfile: .strimrDirectPlay,
        )
        let info: JellyfinPlaybackInfo = try await context.post(
            path: ["Items", item.id, "PlaybackInfo"],
            query: [URLQueryItem(name: "UserId", value: userID)],
            body: body,
        )

        guard info.errorCode == nil,
              let source = info.mediaSources?.first(where: { $0.supportsDirectPlay == true }),
              let playSessionID = info.playSessionID,
              !playSessionID.isEmpty
        else {
            throw JellyfinAPIError.noPlayableSource
        }

        let streamURL = try context.url(
            path: ["Videos", item.id, "stream"],
            query: [
                URLQueryItem(name: "Static", value: "true"),
                URLQueryItem(name: "MediaSourceId", value: source.id),
                URLQueryItem(name: "PlaySessionId", value: playSessionID),
            ],
        )
        let headers = try context.playbackHeaders()

        let externalSubtitles = externalSubtitles(streams: source.mediaStreams ?? [], headers: headers)

        return JellyfinPlaybackPlan(
            item: item,
            url: streamURL,
            headers: headers,
            mediaSourceID: source.id,
            playSessionID: playSessionID,
            initialPosition: resume ? item.resumePosition : nil,
            preferredAudioStreamIndex: source.defaultAudioStreamIndex,
            preferredSubtitleStreamIndex: source.defaultSubtitleStreamIndex,
            chapters: item.chapters ?? [],
            externalSubtitles: externalSubtitles,
        )
    }

    func externalSubtitles(item: JellyfinItem) throws -> [ExternalSubtitleTrack] {
        let headers = try context.playbackHeaders()
        return externalSubtitles(
            streams: (item.mediaSources ?? []).flatMap { $0.mediaStreams ?? [] },
            headers: headers
        )
    }

    private func externalSubtitles(
        streams: [JellyfinMediaStream],
        headers: [String: String]
    ) -> [ExternalSubtitleTrack] {
        streams.compactMap { stream -> ExternalSubtitleTrack? in
            guard stream.type.lowercased() == "subtitle",
                  stream.isExternal == true,
                  stream.deliveryMethod?.lowercased() == "external",
                  let deliveryURL = stream.deliveryURL,
                  let url = URL(string: deliveryURL, relativeTo: context.connection?.baseURL)?.absoluteURL
            else {
                return nil
            }
            return ExternalSubtitleTrack(
                url: url,
                name: stream.displayTitle,
                language: stream.language,
                isForced: stream.isForced ?? false,
                isDefault: stream.isDefault ?? false,
                httpHeaders: headers,
                formatHint: stream.codec,
            )
        }
    }

    func reportStarted(plan: JellyfinPlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        try await sendReport(path: ["Sessions", "Playing"], plan: plan, position: position, isPaused: isPaused)
    }

    func reportProgress(plan: JellyfinPlaybackPlan, position: TimeInterval, isPaused: Bool) async throws {
        try await sendReport(
            path: ["Sessions", "Playing", "Progress"],
            plan: plan,
            position: position,
            isPaused: isPaused,
        )
    }

    func reportStopped(plan: JellyfinPlaybackPlan, position: TimeInterval) async throws {
        let body = JellyfinPlaybackReport(
            itemID: plan.item.id,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: JellyfinTime.ticks(fromSeconds: position),
            isPaused: true,
            playMethod: "DirectPlay",
        )
        let data = try JSONEncoder().encode(body)
        try await context.send(path: ["Sessions", "Playing", "Stopped"], method: "POST", body: data)
    }

    private func sendReport(
        path: [String],
        plan: JellyfinPlaybackPlan,
        position: TimeInterval,
        isPaused: Bool,
    ) async throws {
        let body = JellyfinPlaybackReport(
            itemID: plan.item.id,
            mediaSourceID: plan.mediaSourceID,
            playSessionID: plan.playSessionID,
            positionTicks: JellyfinTime.ticks(fromSeconds: position),
            isPaused: isPaused,
            playMethod: "DirectPlay",
        )
        let data = try JSONEncoder().encode(body)
        try await context.send(path: path, method: "POST", body: data)
    }
}

private struct JellyfinPlaybackInfoRequest: Encodable {
    let userID: String
    let startTimeTicks: Int64
    let isPlayback = true
    let autoOpenLiveStream = true
    let enableDirectPlay = true
    let enableDirectStream = false
    let enableTranscoding = false
    let maxStreamingBitrate = 140_000_000
    let deviceProfile: JellyfinDeviceProfile

    private enum CodingKeys: String, CodingKey {
        case userID = "UserId"
        case startTimeTicks = "StartTimeTicks"
        case isPlayback = "IsPlayback"
        case autoOpenLiveStream = "AutoOpenLiveStream"
        case enableDirectPlay = "EnableDirectPlay"
        case enableDirectStream = "EnableDirectStream"
        case enableTranscoding = "EnableTranscoding"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case deviceProfile = "DeviceProfile"
    }
}

private struct JellyfinDeviceProfile: Encodable {
    let name: String
    let maxStreamingBitrate: Int
    let maxStaticBitrate: Int
    let directPlayProfiles: [DirectPlayProfile]
    let transcodingProfiles: [EmptyProfile]
    let containerProfiles: [EmptyProfile]
    let codecProfiles: [EmptyProfile]
    let subtitleProfiles: [SubtitleProfile]
    let responseProfiles: [EmptyProfile]

    struct DirectPlayProfile: Encodable {
        let container: String
        let audioCodec: String
        let videoCodec: String
        let type: String

        private enum CodingKeys: String, CodingKey {
            case container = "Container"
            case audioCodec = "AudioCodec"
            case videoCodec = "VideoCodec"
            case type = "Type"
        }
    }

    struct SubtitleProfile: Encodable {
        let format: String
        let method: String

        private enum CodingKeys: String, CodingKey {
            case format = "Format"
            case method = "Method"
        }
    }

    struct EmptyProfile: Encodable {}

    private enum CodingKeys: String, CodingKey {
        case name = "Name"
        case maxStreamingBitrate = "MaxStreamingBitrate"
        case maxStaticBitrate = "MaxStaticBitrate"
        case directPlayProfiles = "DirectPlayProfiles"
        case transcodingProfiles = "TranscodingProfiles"
        case containerProfiles = "ContainerProfiles"
        case codecProfiles = "CodecProfiles"
        case subtitleProfiles = "SubtitleProfiles"
        case responseProfiles = "ResponseProfiles"
    }

    static let strimrDirectPlay = JellyfinDeviceProfile(
        name: "Strimr Direct Play",
        maxStreamingBitrate: 140_000_000,
        maxStaticBitrate: 140_000_000,
        directPlayProfiles: [
            DirectPlayProfile(
                container: "mp4,m4v,mov,mkv,webm,avi,mpegts,ts,m2ts",
                audioCodec: "aac,ac3,eac3,truehd,dts,flac,opus,vorbis,mp3,alac,pcm_s16le,pcm_s24le",
                videoCodec: "h264,hevc,av1,vp8,vp9,mpeg2video,mpeg4,vc1",
                type: "Video",
            ),
        ],
        transcodingProfiles: [],
        containerProfiles: [],
        codecProfiles: [],
        subtitleProfiles: [
            SubtitleProfile(format: "srt", method: "External"),
            SubtitleProfile(format: "ass", method: "External"),
            SubtitleProfile(format: "ssa", method: "External"),
            SubtitleProfile(format: "vtt", method: "External"),
            SubtitleProfile(format: "subrip", method: "Embed"),
            SubtitleProfile(format: "ass", method: "Embed"),
            SubtitleProfile(format: "pgssub", method: "Embed"),
            SubtitleProfile(format: "dvdsub", method: "Embed"),
        ],
        responseProfiles: [],
    )
}

private struct JellyfinPlaybackReport: Encodable {
    let itemID: String
    let mediaSourceID: String
    let playSessionID: String
    let positionTicks: Int64
    let isPaused: Bool
    let playMethod: String
    let canSeek = true
    let isMuted = false
    let repeatMode = "RepeatNone"

    private enum CodingKeys: String, CodingKey {
        case itemID = "ItemId"
        case mediaSourceID = "MediaSourceId"
        case playSessionID = "PlaySessionId"
        case positionTicks = "PositionTicks"
        case isPaused = "IsPaused"
        case playMethod = "PlayMethod"
        case canSeek = "CanSeek"
        case isMuted = "IsMuted"
        case repeatMode = "RepeatMode"
    }
}
