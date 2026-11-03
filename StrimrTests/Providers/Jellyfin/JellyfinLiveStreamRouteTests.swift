import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinLiveStreamRouteTests {
    private let baseURL = URL(string: "https://jellyfin.example.invalid/jf")!

    private func source(_ fixture: String) throws -> JellyfinMediaSource {
        let info = try Fixtures.decode(JellyfinPlaybackInfo.self, from: fixture)
        return try #require(info.mediaSources?.first)
    }

    @Test func `streams the tuner TS through the server when direct stream is allowed`() throws {
        let route = try #require(JellyfinLiveStreamRoute.resolve(
            source: source("jellyfin-live-playbackinfo-directstream"),
            itemID: "channel-1",
            playSessionID: "play-session-1",
            baseURL: baseURL,
        ))

        #expect(route.kind == .directStream)
        #expect(route.playMethod == "DirectStream")
        #expect(route.playbackRoute == .directStream)
        #expect(!route.nativeRemoteHLS)
        #expect(route.usesJellyfinServer)
        let components = try #require(URLComponents(url: route.url, resolvingAgainstBaseURL: false))
        #expect(components.path == "/jf/Videos/channel-1/stream.ts")
        let query = Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value) })
        #expect(query["static"] == "true")
        #expect(query["mediaSourceId"] == "source-1")
        #expect(query["liveStreamId"] == "live-stream-1")
        #expect(query["playSessionId"] == "play-session-1")
    }

    @Test func `reads a third-party HLS origin directly`() throws {
        let route = try #require(JellyfinLiveStreamRoute.resolve(
            source: source("jellyfin-live-playbackinfo-remotehls"),
            itemID: "channel-2",
            playSessionID: "play-session-2",
            baseURL: baseURL,
        ))

        #expect(route.kind == .remoteHLS)
        #expect(route.playMethod == "DirectPlay")
        #expect(route.nativeRemoteHLS)
        #expect(!route.usesJellyfinServer)
        #expect(route.url.absoluteString == "https://iptv.example.invalid/channel/index.m3u8")
    }

    @Test func `falls back to the server transcode`() throws {
        let route = try #require(JellyfinLiveStreamRoute.resolve(
            source: source("jellyfin-live-playbackinfo-transcode"),
            itemID: "channel-3",
            playSessionID: "play-session-3",
            baseURL: baseURL,
        ))

        #expect(route.kind == .transcode)
        #expect(route.playMethod == "Transcode")
        #expect(route.nativeRemoteHLS)
        #expect(route.url.host == "jellyfin.example.invalid")
        #expect(route.url.path == "/videos/channel-3/live.m3u8")
    }

    @Test func `a forced transcode skips the direct stream`() throws {
        let route = try JellyfinLiveStreamRoute.resolve(
            source: source("jellyfin-live-playbackinfo-directstream"),
            itemID: "channel-1",
            playSessionID: "play-session-1",
            baseURL: baseURL,
            preference: .serverTranscode,
        )

        #expect(route == nil)
    }

    @Test func `reads interlacing from the video stream`() throws {
        let video = try source("jellyfin-live-playbackinfo-directstream").mediaStreams?.first
        #expect(video?.isInterlaced == true)
    }
}
