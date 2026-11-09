import Foundation

/// Where a Jellyfin live channel is read from, picked from its `PlaybackInfo` media source.
struct JellyfinLiveStreamRoute: Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        /// The tuner's MPEG-TS, passed through by the Jellyfin server.
        case directStream
        /// A third-party HLS origin, read without the Jellyfin server.
        case remoteHLS
        case transcode
    }

    let kind: Kind
    let url: URL

    var playMethod: String {
        switch kind {
        case .directStream: "DirectStream"
        case .remoteHLS: "DirectPlay"
        case .transcode: "Transcode"
        }
    }

    var playbackRoute: LiveTVPlaybackRoute {
        switch kind {
        case .directStream: .directStream
        case .remoteHLS: .directPlay
        case .transcode: .transcode
        }
    }

    /// AVPlayer reads HLS on its own; the engine demuxes the TS stream.
    var nativeRemoteHLS: Bool {
        kind != .directStream
    }

    var usesJellyfinServer: Bool {
        kind != .remoteHLS
    }

    static func resolve(
        source: JellyfinMediaSource,
        itemID: String,
        playSessionID: String,
        baseURL: URL,
        preference: LiveTVRoutePreference = .automatic,
    ) -> JellyfinLiveStreamRoute? {
        if preference == .automatic {
            if source.supportsDirectStream == true,
               let url = directStreamURL(source: source, itemID: itemID, playSessionID: playSessionID, baseURL: baseURL)
            {
                return JellyfinLiveStreamRoute(kind: .directStream, url: url)
            }
            if let url = remoteHLSURL(source: source) {
                return JellyfinLiveStreamRoute(kind: .remoteHLS, url: url)
            }
        }
        if let rawURL = source.transcodingURL, let url = transcodingURL(rawURL, baseURL: baseURL) {
            return JellyfinLiveStreamRoute(kind: .transcode, url: url)
        }
        return nil
    }

    /// The server returns this path from its root, without the base path it may be installed under.
    private static func transcodingURL(_ rawURL: String, baseURL: URL) -> URL? {
        guard rawURL.hasPrefix("/") else { return URL(string: rawURL, relativeTo: baseURL)?.absoluteURL }
        let base = baseURL.absoluteString
        return URL(string: (base.hasSuffix("/") ? String(base.dropLast()) : base) + rawURL)
    }

    private static func directStreamURL(
        source: JellyfinMediaSource,
        itemID: String,
        playSessionID: String,
        baseURL: URL,
    ) -> URL? {
        var components = URLComponents(
            url: baseURL.appendingPathComponent("Videos").appendingPathComponent(itemID)
                .appendingPathComponent("stream.ts"),
            resolvingAgainstBaseURL: false,
        )
        var query = [
            URLQueryItem(name: "static", value: "true"),
            URLQueryItem(name: "mediaSourceId", value: source.id),
            URLQueryItem(name: "playSessionId", value: playSessionID),
        ]
        if let liveStreamID = source.liveStreamID, !liveStreamID.isEmpty {
            query.append(URLQueryItem(name: "liveStreamId", value: liveStreamID))
        }
        components?.queryItems = query
        return components?.url
    }

    private static func remoteHLSURL(source: JellyfinMediaSource) -> URL? {
        guard let rawPath = source.path,
              let url = URL(string: rawPath),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              source.container?.lowercased() == "hls" || url.pathExtension.lowercased() == "m3u8"
        else { return nil }
        return url
    }
}
