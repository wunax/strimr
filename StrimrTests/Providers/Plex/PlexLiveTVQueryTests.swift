import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexLiveTVQueryTests {
    private let client = PlexLiveTVQuery.Client(
        clientIdentifier: "client-1",
        productVersion: "1.0",
        supportsHEVC: true,
    )

    private func decision(_ name: String) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: Fixtures.data(name)) as? [String: Any])
    }

    private func items(directPlay: Bool, offset: TimeInterval? = nil) -> [URLQueryItem] {
        PlexLiveTVQuery.items(
            sessionPath: "/livetv/sessions/session-1",
            sessionIdentifier: "session-identifier",
            transcodeSessionID: "transcode-1",
            directPlay: directPlay,
            offset: offset,
            client: client,
            profile: PlexLiveTVQuery.profile(supportsHEVC: true),
            burnsSubtitles: false,
        )
    }

    @Test func `offers MPEG-TS direct play over HLS and HTTP with a copying fallback`() {
        let profile = PlexLiveTVQuery.profile(supportsHEVC: true)
        let clauses = profile.components(separatedBy: "+")

        #expect(clauses.count == 5)
        #expect(clauses.filter { $0.hasPrefix("add-direct-play-profile(") }.count == 2)
        #expect(profile.contains("protocol=hls&videoCodec=h264,hevc,mpeg2video&audioCodec=aac,ac3,eac3,mp2,mp3,dts"))
        #expect(profile.contains("protocol=http&videoCodec=h264,hevc,mpeg2video"))
        #expect(profile.contains("subtitleCodec=dvb_teletext,dvb_subtitle,eia_608"))
        #expect(profile.contains("videoCodec=h264,hevc,mpeg2video&audioCodec=aac,ac3,eac3,mp2,mp3,dts&replace=true"))
        #expect(profile.contains("subtitleCodec=webvtt"))
    }

    @Test func `leaves HEVC out where the device cannot decode it`() {
        let profile = PlexLiveTVQuery.profile(supportsHEVC: false)

        #expect(!profile.contains("hevc"))
        #expect(profile.contains("videoCodec=h264,mpeg2video"))
    }

    @Test func `encodes the plus and commas of the client profile`() {
        let query = PlexLiveTVQuery.percentEncodedQuery(items(directPlay: true))
        let profile = query.components(separatedBy: "&")
            .first { $0.hasPrefix("X-Plex-Client-Profile-Extra=") }

        #expect(profile?.contains("+") == false)
        #expect(profile?.contains(",") == false)
        #expect(profile?.contains("%2B") == true)
        #expect(profile?.contains("%2C") == true)
        let decoded = profile?.dropFirst("X-Plex-Client-Profile-Extra=".count).removingPercentEncoding
        #expect(decoded == PlexLiveTVQuery.profile(supportsHEVC: true))
    }

    @Test func `decision and start share their parameters`() {
        let decision = items(directPlay: true)
        let start = items(directPlay: true)

        #expect(decision == start)
        #expect(decision.first { $0.name == "directPlay" }?.value == "1")
        #expect(items(directPlay: false).first { $0.name == "directPlay" }?.value == "0")
        #expect(decision.first { $0.name == "offset" } == nil)
        #expect(items(directPlay: false, offset: 90).first { $0.name == "offset" }?.value == "90")
    }

    @Test func `reads the live session part when direct play is granted`() throws {
        let key = try PlexLiveTVQuery.directPlayPartKey(fromDecision: decision("plex-livetv-decision-directplay"))

        #expect(key == "/livetv/sessions/session-1/client-1/index.m3u8")
    }

    @Test func `ignores the part when the server transcodes`() throws {
        let key = try PlexLiveTVQuery.directPlayPartKey(fromDecision: decision("plex-livetv-decision-transcode"))

        #expect(key == nil)
    }

    @Test func `builds the direct play URL with the session and token`() throws {
        let url = try #require(PlexLiveTVQuery.directPlayURL(
            baseURL: URL(string: "https://plex.example.invalid:32400")!,
            partKey: "/livetv/sessions/session-1/client-1/index.m3u8",
            sessionIdentifier: "session-identifier",
            token: "token",
        ))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))

        #expect(components.path == "/livetv/sessions/session-1/client-1/index.m3u8")
        #expect(components.queryItems?.contains(URLQueryItem(name: "X-Plex-Token", value: "token")) == true)
        #expect(components.queryItems?.contains(
            URLQueryItem(name: "X-Plex-Session-Identifier", value: "session-identifier"),
        ) == true)
    }

    @Test func `reads interlacing from the tuned video stream`() {
        let metadata: [String: Any] = [
            "Media": [["Part": [["Stream": [
                ["streamType": 1, "codec": "mpeg2video", "scanType": "interlaced"],
                ["streamType": 2, "codec": "mp2"],
            ]]]]],
        ]

        #expect(PlexLiveTVQuery.isInterlaced(tuneMetadata: metadata))
        #expect(!PlexLiveTVQuery.isInterlaced(tuneMetadata: ["Media": [["scanType": "progressive"]]]))
    }
}
