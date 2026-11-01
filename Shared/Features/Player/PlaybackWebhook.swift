import Foundation

/// The optional Notify URL: a small JSON POST for each playback event. Delivery is fire and forget.
nonisolated enum PlaybackWebhook {
    enum Event: String, Codable, Sendable {
        case start
        case pause
        case resume
        case stop
        /// Playback reached the end, as opposed to `stop`, which leaves before it.
        case finish
    }

    struct Payload: Codable, Equatable, Sendable {
        let event: Event
        let provider: String
        let server: String
        let ratingKey: String
        let type: String
        let title: String
        let position: TimeInterval
        /// Left out when unknown.
        let duration: TimeInterval?
    }

    static let timeout: TimeInterval = 3

    /// Only http and https addresses with a host are used; anything else turns the notification off.
    static func endpoint(from setting: String) -> URL? {
        let text = setting.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: text),
              let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
              url.host?.isEmpty == false
        else { return nil }
        return url
    }

    static func request(for payload: Payload, to url: URL) throws -> URLRequest {
        var request = URLRequest(url: url, timeoutInterval: timeout)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(payload)
        return request
    }

    /// Never blocks and never reports a failure. A transport error is retried once; an HTTP error status is not,
    /// since the receiver did get the message.
    static func send(_ payload: Payload, to url: URL, session: URLSession = .shared) {
        guard let request = try? request(for: payload, to: url) else { return }
        Task.detached(priority: .utility) {
            if (try? await session.data(for: request)) == nil {
                _ = try? await session.data(for: request)
            }
        }
    }
}

/// Turns the player's pause state and its end into webhook events, each at most once in a row.
nonisolated struct PlaybackWebhookTracker: Equatable {
    private var started = false
    private var paused = false
    private var closed = false

    /// `start` on the first playing state, then `pause` and `resume` as the state flips.
    mutating func event(isPaused: Bool) -> PlaybackWebhook.Event? {
        guard !closed else { return nil }
        if !started {
            guard !isPaused else { return nil }
            started = true
            return .start
        }
        guard isPaused != paused else { return nil }
        paused = isPaused
        return isPaused ? .pause : .resume
    }

    /// `finish` or `stop`, once. Nothing when playback never started, e.g. after a load error.
    mutating func close(finished: Bool) -> PlaybackWebhook.Event? {
        guard started, !closed else { return nil }
        closed = true
        return finished ? .finish : .stop
    }
}
