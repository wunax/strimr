import Foundation

/// The x-callback-url opened by an external player when it closes. Strimr adds the item to the callback URL,
/// which players keep, then reads the standard parameters they append.
nonisolated struct ExternalPlaybackCallback: Equatable, Sendable {
    enum Outcome: Equatable, Sendable {
        /// Players that report nothing on success leave both values nil.
        case finished(position: TimeInterval?, progress: Double?)
        case failed(message: String?)
    }

    let item: MediaIdentity?
    let duration: TimeInterval?
    let outcome: Outcome

    private static let scheme = "strimr"
    private static let host = "x-callback-url"
    private static let path = "/playbackDidFinish"

    static func url(for target: ExternalPlaybackTarget) -> URL {
        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = path
        var queryItems = [
            URLQueryItem(name: "server", value: target.item.server.stableKey),
            URLQueryItem(name: "item", value: target.item.itemID),
        ]
        if let duration = target.duration, duration > 0 {
            queryItems.append(URLQueryItem(name: "duration", value: String(Int(duration))))
        }
        components.queryItems = queryItems
        return components.url!
    }
}

nonisolated extension ExternalPlaybackCallback {
    init?(url: URL) {
        guard url.scheme == Self.scheme, url.host == Self.host, url.path == Self.path,
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let query = Dictionary(
            (components.queryItems ?? []).compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first },
        )
        if let server = query["server"].flatMap(ServerIdentity.init(stableKey:)), let itemID = query["item"] {
            item = MediaIdentity(server: server, itemID: itemID)
        } else {
            item = nil
        }
        duration = query["duration"].flatMap(TimeInterval.init)
        if query["errorCode"] != nil || query["errorMessage"] != nil {
            outcome = .failed(message: query["errorMessage"].flatMap { $0.isEmpty ? nil : $0 })
        } else {
            outcome = .finished(
                position: query["position"].flatMap(TimeInterval.init),
                progress: query["progress"].flatMap(Double.init),
            )
        }
    }
}
