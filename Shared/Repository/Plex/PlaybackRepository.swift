import Foundation

final class PlaybackRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    enum PlaybackState: String {
        case playing
        case buffering
        case paused
        case stopped
    }

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        self.context = context
        network = PlexServerNetworkClient(context: context)
    }

    func setPreferredStreams(
        partId: Int,
        audioStreamId: Int? = nil,
        subtitleStreamId: Int? = nil,
        applyToAllParts: Bool = true,
    ) async throws {
        var queryItems: [URLQueryItem] = []

        if let audioStreamId {
            queryItems.append(URLQueryItem(name: "audioStreamID", value: String(audioStreamId)))
        }

        if let subtitleStreamId {
            queryItems.append(URLQueryItem(name: "subtitleStreamID", value: String(subtitleStreamId)))
        }

        queryItems.append(URLQueryItem(name: "allParts", value: applyToAllParts ? "1" : "0"))

        try await network.send(
            path: "/library/parts/\(partId)",
            queryItems: queryItems,
            method: "PUT",
        )
    }

    func setPreferredSubtitleStream(
        partId: Int,
        subtitleStreamId: Int?,
        applyToAllParts: Bool = true,
    ) async throws {
        try await setPreferredStreams(
            partId: partId,
            subtitleStreamId: subtitleStreamId ?? 0,
            applyToAllParts: applyToAllParts,
        )
    }

    func updateTimeline(
        ratingKey: String,
        state: PlaybackState,
        time: Int,
        duration: Int,
        sessionIdentifier: String,
        playQueueItemID: Int? = nil,
    ) async throws -> PlexTimelineResponse {
        var queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "duration", value: String(duration)),
        ]
        if let playQueueItemID {
            queryItems.append(URLQueryItem(name: "playQueueItemID", value: String(playQueueItemID)))
        }

        return try await network.request(
            path: "/:/timeline",
            queryItems: queryItems,
            headers: [
                "X-Plex-Session-Identifier": sessionIdentifier,
            ],
        )
    }

    func transcodeURL(
        ratingKey: String,
        mediaIndex: Int,
        partIndex: Int,
        quality: TranscodeQualityPreset,
        playbackSessionIdentifier: String,
        transcodeSessionIdentifier: String,
        audioStreamID: Int?,
        burnsSubtitles: Bool,
    ) async throws -> URL? {
        guard !quality.isOriginal else { return nil }
        var query = transcodeQuery(
            ratingKey: ratingKey,
            mediaIndex: mediaIndex,
            partIndex: partIndex,
            quality: quality,
            playbackSessionIdentifier: playbackSessionIdentifier,
            transcodeSessionIdentifier: transcodeSessionIdentifier,
            audioStreamID: audioStreamID,
            burnsSubtitles: burnsSubtitles,
            usesTransportStreamFallback: false,
        )
        var decision: PlexTranscodeDecisionResponse = try await network.request(
            path: "/video/:/transcode/universal/decision",
            queryItems: query,
            headers: ["Accept-Language": "en", "Accept": "application/json"],
        )
        guard decision.mediaContainer.allowsTranscode else { return nil }
        if decision.mediaContainer.selectedContainer?.lowercased() != "mp4" {
            query = transcodeQuery(
                ratingKey: ratingKey,
                mediaIndex: mediaIndex,
                partIndex: partIndex,
                quality: quality,
                playbackSessionIdentifier: playbackSessionIdentifier,
                transcodeSessionIdentifier: transcodeSessionIdentifier,
                audioStreamID: audioStreamID,
                burnsSubtitles: burnsSubtitles,
                usesTransportStreamFallback: true,
            )
            decision = try await network.request(
                path: "/video/:/transcode/universal/decision",
                queryItems: query,
                headers: ["Accept-Language": "en", "Accept": "application/json"],
            )
            guard decision.mediaContainer.allowsTranscode,
                  decision.mediaContainer.selectedContainer?.lowercased() == "mpegts"
            else { return nil }
        }
        guard let snapshot = try? context?.serverAccessSnapshot(),
              var components = URLComponents(
                  url: snapshot.baseURL.appendingPathComponent("video/:/transcode/universal/start.m3u8"),
                  resolvingAgainstBaseURL: false,
              )
        else { throw PlexAPIError.invalidURL }
        components.queryItems = query + [
            URLQueryItem(name: "X-Plex-Token", value: snapshot.authToken),
        ]
        guard let url = components.url else { throw PlexAPIError.invalidURL }
        return url
    }

    func pingTranscode(sessionIdentifier: String) async throws {
        try await network.send(
            path: "/video/:/transcode/universal/ping",
            queryItems: [URLQueryItem(name: "session", value: sessionIdentifier)],
        )
    }

    func stopTranscode(sessionIdentifier: String) async throws {
        try await network.send(
            path: "/video/:/transcode/universal/stop",
            queryItems: [URLQueryItem(name: "session", value: sessionIdentifier)],
        )
    }

    private func transcodeQuery(
        ratingKey: String,
        mediaIndex: Int,
        partIndex: Int,
        quality: TranscodeQualityPreset,
        playbackSessionIdentifier: String,
        transcodeSessionIdentifier: String,
        audioStreamID: Int?,
        burnsSubtitles: Bool,
        usesTransportStreamFallback: Bool,
    ) -> [URLQueryItem] {
        let bitrate = quality.maximumVideoBitrateKbps ?? 12_000
        let videoTarget = if usesTransportStreamFallback {
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264&audioCodec=aac,ac3,eac3,mp3)"
        } else {
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mp4&videoCodec=h264,hevc&audioCodec=aac,ac3,eac3,mp3)"
        }
        let profile = [
            "add-settings(DirectPlayStreamSelection=true)",
            "add-limitation(scope=videoCodec&scopeName=*&type=upperBound&name=video.bitrate&value=\(bitrate)&replace=true)",
            videoTarget,
            "add-transcode-target(type=subtitleProfile&context=streaming&protocol=hls&container=webvtt&subtitleCodec=webvtt)",
        ].joined(separator: "+")
        var values = [
            URLQueryItem(name: "hasMDE", value: "1"),
            URLQueryItem(name: "path", value: "/library/metadata/\(ratingKey)"),
            URLQueryItem(name: "mediaIndex", value: String(mediaIndex)),
            URLQueryItem(name: "partIndex", value: String(partIndex)),
            URLQueryItem(name: "protocol", value: "hls"),
            URLQueryItem(name: "fastSeek", value: "1"),
            URLQueryItem(name: "directPlay", value: "0"),
            URLQueryItem(name: "directStream", value: "0"),
            URLQueryItem(name: "directStreamAudio", value: "1"),
            URLQueryItem(name: "maxVideoBitrate", value: String(bitrate)),
            URLQueryItem(name: "videoResolution", value: quality.plexVideoResolution),
            URLQueryItem(name: "videoQuality", value: quality.plexVideoQuality.map(String.init)),
            URLQueryItem(name: "subtitleSize", value: "100"),
            URLQueryItem(name: "audioBoost", value: "100"),
            URLQueryItem(name: "location", value: "lan"),
            URLQueryItem(name: "autoAdjustQuality", value: "0"),
            URLQueryItem(name: "mediaBufferSize", value: "102400"),
            URLQueryItem(name: "session", value: transcodeSessionIdentifier),
            URLQueryItem(name: "subtitles", value: burnsSubtitles ? "burn" : "none"),
            URLQueryItem(name: "X-Plex-Session-Identifier", value: playbackSessionIdentifier),
            URLQueryItem(name: "X-Plex-Client-Profile-Extra", value: profile),
            URLQueryItem(name: "X-Plex-Incomplete-Segments", value: "1"),
            URLQueryItem(name: "X-Plex-Features", value: "external-media,indirect-media"),
            URLQueryItem(name: "X-Plex-Client-Profile-Name", value: "Generic"),
        ]
        if let audioStreamID {
            values.append(URLQueryItem(name: "audioStreamID", value: String(audioStreamID)))
        }
        return values
    }
}

private extension TranscodeQualityPreset {
    var plexVideoResolution: String? {
        switch self {
        case .original: nil
        case .p240_320: "420x240"
        case .p360_700: "640x360"
        case .p480_1_5mbps: "720x480"
        case .p720_2mbps, .p720_4mbps: "1280x720"
        case .p1080_8mbps, .p1080_12mbps: "1920x1080"
        }
    }

    var plexVideoQuality: Int? {
        switch self {
        case .original: nil
        case .p240_320: 30
        case .p360_700: 40
        case .p480_1_5mbps, .p720_2mbps, .p1080_8mbps: 60
        case .p1080_12mbps: 90
        case .p720_4mbps: 100
        }
    }
}

private struct PlexTranscodeDecisionResponse: Decodable {
    let mediaContainer: MediaContainer

    struct MediaContainer: Decodable {
        let generalDecisionCode: Int?
        let transcodeDecisionCode: Int?
        let mdeDecisionCode: Int?
        let metadata: [Metadata]?

        var selectedContainer: String? {
            metadata?.first?.media?.first?.container
        }

        var allowsTranscode: Bool {
            let codes = [generalDecisionCode, transcodeDecisionCode, mdeDecisionCode].compactMap { $0 }
            guard !codes.contains(where: { $0 >= 2_000 }) else { return false }
            if transcodeDecisionCode == 1_000 || generalDecisionCode == 1_000 { return false }
            return transcodeDecisionCode == 1_001 || generalDecisionCode == 1_001 || !codes.isEmpty
        }

        struct Metadata: Decodable {
            let media: [Media]?

            struct Media: Decodable {
                let container: String?
            }

            private enum CodingKeys: String, CodingKey {
                case media = "Media"
            }
        }

        private enum CodingKeys: String, CodingKey {
            case generalDecisionCode
            case transcodeDecisionCode
            case mdeDecisionCode
            case metadata = "Metadata"
        }

        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            generalDecisionCode = container.flexibleInt(forKey: .generalDecisionCode)
            transcodeDecisionCode = container.flexibleInt(forKey: .transcodeDecisionCode)
            mdeDecisionCode = container.flexibleInt(forKey: .mdeDecisionCode)
            metadata = try container.decodeIfPresent([Metadata].self, forKey: .metadata)
        }
    }

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private extension KeyedDecodingContainer {
    func flexibleInt(forKey key: Key) -> Int? {
        if let value = try? decode(Int.self, forKey: key) { return value }
        if let value = try? decode(String.self, forKey: key) { return Int(value) }
        return nil
    }
}
