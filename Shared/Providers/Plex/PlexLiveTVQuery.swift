import Foundation

/// Parameters of the Plex Live TV `/decision` and `start.m3u8` requests, which must match.
enum PlexLiveTVQuery {
    struct Client: Equatable {
        let clientIdentifier: String
        let productVersion: String?
        let supportsHEVC: Bool
    }

    static func profile(supportsHEVC: Bool) -> String {
        let videoCodecs = (supportsHEVC ? ["h264", "hevc", "mpeg2video"] : ["h264", "mpeg2video"])
            .joined(separator: ",")
        let audioCodecs = "aac,ac3,eac3,mp2,mp3,dts"
        let directPlay = { (protocolName: String) in
            "add-direct-play-profile(type=videoProfile&container=mpegts&protocol=\(protocolName)"
                + "&videoCodec=\(videoCodecs)&audioCodec=\(audioCodecs)"
                + "&subtitleCodec=dvb_teletext,dvb_subtitle,eia_608)"
        }
        return [
            "add-settings(DirectPlayStreamSelection=true)",
            directPlay("hls"),
            directPlay("http"),
            // h264 comes first so the server only encodes to it; the other codecs are copied.
            "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts"
                + "&videoCodec=\(videoCodecs)&audioCodec=\(audioCodecs)&replace=true)",
            "add-transcode-target(type=subtitleProfile&context=streaming&protocol=hls&container=webvtt"
                + "&subtitleCodec=webvtt)",
        ].joined(separator: "+")
    }

    /// The server-transcoded profile, which AVPlayer can read directly.
    static let transcodeProfile = [
        "add-settings(DirectPlayStreamSelection=true)",
        "add-transcode-target(type=videoProfile&context=streaming&protocol=hls&container=mpegts&videoCodec=h264"
            + "&audioCodec=aac,ac3,eac3,mp3)",
        "add-transcode-target(type=subtitleProfile&context=streaming&protocol=hls&container=webvtt"
            + "&subtitleCodec=webvtt)",
    ].joined(separator: "+")

    static func items(
        sessionPath: String,
        sessionIdentifier: String,
        transcodeSessionID: String,
        directPlay: Bool,
        offset: TimeInterval?,
        client: Client,
        profile: String,
        burnsSubtitles: Bool,
    ) -> [URLQueryItem] {
        var query: [URLQueryItem] = [
            .init(name: "hasMDE", value: "1"), .init(name: "path", value: sessionPath),
            .init(name: "mediaIndex", value: "0"), .init(name: "partIndex", value: "0"),
            .init(name: "protocol", value: "hls"), .init(name: "fastSeek", value: "1"),
            .init(name: "directPlay", value: directPlay ? "1" : "0"), .init(name: "directStream", value: "1"),
            .init(name: "directStreamAudio", value: "1"),
            .init(name: "subtitles", value: burnsSubtitles ? "burn" : "none"),
            .init(name: "session", value: transcodeSessionID),
            .init(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
            .init(name: "X-Plex-Client-Identifier", value: client.clientIdentifier),
            .init(name: "X-Plex-Product", value: "Strimr"),
            .init(name: "X-Plex-Version", value: client.productVersion),
            .init(name: "X-Plex-Platform", value: "Generic"),
            .init(name: "X-Plex-Client-Profile-Name", value: "Generic"),
            .init(name: "X-Plex-Client-Profile-Extra", value: profile),
            .init(name: "X-Plex-Incomplete-Segments", value: "1"),
        ]
        if let offset {
            query.append(.init(name: "offset", value: String(Int(offset))))
        }
        return query
    }

    /// `URLComponents` keeps `+` and `,` as is; PMS reads a bare `+` as a space and would cut the profile.
    static func percentEncodedQuery(_ items: [URLQueryItem]) -> String {
        items.map { item in
            let name = encode(item.name)
            guard let value = item.value else { return name }
            return "\(name)=\(encode(value))"
        }.joined(separator: "&")
    }

    /// The live session part PMS lets the client read without a transcoder, when it grants direct play.
    static func directPlayPartKey(fromDecision root: [String: Any]) -> String? {
        let container = root["MediaContainer"] as? [String: Any] ?? root
        guard intValue(container["mdeDecisionCode"]) == 1000 else { return nil }
        let parts = list(container["Metadata"])
            .flatMap { list($0["Media"]) }
            .flatMap { list($0["Part"]) }
        return parts.lazy
            .filter { ($0["decision"] as? String)?.lowercased() == "directplay" }
            .compactMap { $0["key"] as? String }
            .first { $0.hasPrefix("/livetv/sessions/") }
    }

    /// The tune response's video stream reports `scanType`; the engine decodes interlaced video in software.
    static func isInterlaced(tuneMetadata metadata: [String: Any]) -> Bool {
        let streams = list(metadata["Media"])
            .flatMap { list($0["Part"]) }
            .flatMap { list($0["Stream"]) } + list(metadata["Stream"])
        let video = streams.first { intValue($0["streamType"]) == 1 }
            ?? list(metadata["Media"]).first
        return (video?["scanType"] as? String)?.lowercased() == "interlaced"
    }

    static func directPlayURL(
        baseURL: URL,
        partKey: String,
        sessionIdentifier: String,
        token: String,
    ) -> URL? {
        guard let part = URLComponents(string: partKey),
              var components = URLComponents(
                  url: baseURL.appendingPathComponent(part.path),
                  resolvingAgainstBaseURL: false,
              )
        else { return nil }
        components.queryItems = (part.queryItems ?? []) + [
            URLQueryItem(name: "X-Plex-Session-Identifier", value: sessionIdentifier),
            URLQueryItem(name: "X-Plex-Token", value: token),
        ]
        return components.url
    }

    private static let unreserved = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~")

    private static func encode(_ value: String) -> String {
        value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
    }

    private static func list(_ value: Any?) -> [[String: Any]] {
        if let values = value as? [[String: Any]] {
            return values
        }
        if let value = value as? [String: Any] {
            return [value]
        }
        return []
    }

    private static func intValue(_ value: Any?) -> Int? {
        switch value {
        case let value as NSNumber: value.intValue
        case let value as String: Int(value)
        default: nil
        }
    }
}
