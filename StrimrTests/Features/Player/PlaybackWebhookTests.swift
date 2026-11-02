import Foundation
@testable import Strimr
import Testing

struct PlaybackWebhookTests {
    private let payload = PlaybackWebhook.Payload(
        event: .pause,
        provider: "plex",
        server: "server-1",
        ratingKey: "42",
        type: "episode",
        title: "Pilot",
        position: 61.5,
        duration: 3600,
    )

    @Test func `only http and https addresses with a host are accepted`() {
        #expect(PlaybackWebhook.endpoint(from: "http://ha.local:8123/api/webhook/x")?.host == "ha.local")
        #expect(PlaybackWebhook.endpoint(from: "  HTTPS://example.com/hook \n")?.scheme == "https")
        #expect(PlaybackWebhook.endpoint(from: "") == nil)
        #expect(PlaybackWebhook.endpoint(from: "ftp://example.com/x") == nil)
        #expect(PlaybackWebhook.endpoint(from: "file:///etc/passwd") == nil)
        #expect(PlaybackWebhook.endpoint(from: "strimr://control/pause") == nil)
        #expect(PlaybackWebhook.endpoint(from: "example.com/hook") == nil)
        #expect(PlaybackWebhook.endpoint(from: "http://") == nil)
    }

    @Test func `the request is a short JSON POST with the documented fields`() throws {
        let url = try #require(URL(string: "http://host/hook"))
        let request = try PlaybackWebhook.request(for: payload, to: url)
        let body = try #require(request.httpBody)
        let json = try #require(JSONSerialization.jsonObject(with: body) as? [String: Any])

        #expect(request.httpMethod == "POST")
        #expect(request.timeoutInterval == PlaybackWebhook.timeout)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
        #expect(Set(json.keys) == ["event", "provider", "server", "ratingKey", "type", "title", "position", "duration"])
        #expect(json["event"] as? String == "pause")
        #expect(json["position"] as? Double == 61.5)
    }

    @Test func `an unknown duration is left out`() throws {
        let unknown = PlaybackWebhook.Payload(
            event: .start,
            provider: "plex",
            server: "s",
            ratingKey: "1",
            type: "movie",
            title: "T",
            position: 0,
            duration: nil,
        )
        let json = try #require(JSONSerialization.jsonObject(with: JSONEncoder().encode(unknown)) as? [String: Any])

        #expect(json["duration"] == nil)
    }

    @Test func `starts once, then pauses and resumes as the state flips`() {
        var tracker = PlaybackWebhookTracker()

        #expect(tracker.event(isPaused: true) == nil)
        #expect(tracker.event(isPaused: false) == .start)
        #expect(tracker.event(isPaused: false) == nil)
        #expect(tracker.event(isPaused: true) == .pause)
        #expect(tracker.event(isPaused: true) == nil)
        #expect(tracker.event(isPaused: false) == .resume)
    }

    @Test func `reports the end once, as finish or stop`() {
        var finished = PlaybackWebhookTracker()
        _ = finished.event(isPaused: false)
        #expect(finished.close(finished: true) == .finish)
        // The player closing after the end must not add a stop.
        #expect(finished.close(finished: false) == nil)
        #expect(finished.event(isPaused: true) == nil)

        var stopped = PlaybackWebhookTracker()
        _ = stopped.event(isPaused: false)
        #expect(stopped.close(finished: false) == .stop)
    }

    @Test func `a playback that never started reports nothing`() {
        var tracker = PlaybackWebhookTracker()

        #expect(tracker.close(finished: false) == nil)
    }
}
