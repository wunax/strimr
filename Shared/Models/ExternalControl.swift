import Foundation

nonisolated extension URL {
    /// The first value of each query parameter.
    var queryValues: [String: String] {
        let items = URLComponents(url: self, resolvingAgainstBaseURL: false)?.queryItems ?? []
        return items.reduce(into: [:]) { values, item in
            if let value = item.value, values[item.name] == nil {
                values[item.name] = value
            }
        }
    }
}

/// A command for the player that is open, from `strimr://control/<action>`.
nonisolated enum ExternalControlCommand: Equatable, Sendable {
    case pause
    case resume
    case toggle
    case seekTo(TimeInterval)
    case seekBy(TimeInterval)
    case skipIntro
    case skipCredits
    case next

    init?(url: URL) {
        guard url.scheme == "strimr", url.host == "control",
              let action = url.pathComponents.dropFirst().first
        else { return nil }
        let query = url.queryValues
        switch action {
        case "pause": self = .pause
        case "resume": self = .resume
        case "toggle": self = .toggle
        case "skipIntro": self = .skipIntro
        case "skipCredits": self = .skipCredits
        case "next": self = .next
        case "seek":
            // `to` wins over `by` when a link carries both.
            if let time = query["to"].flatMap(Self.seconds), time >= 0 {
                self = .seekTo(time)
            } else if let delta = query["by"].flatMap(Self.seconds) {
                self = .seekBy(delta)
            } else {
                return nil
            }
        default: return nil
        }
    }

    /// Rejects `nan` and `inf`, which `Double` would parse.
    static func seconds(_ value: String) -> TimeInterval? {
        Double(value).flatMap { $0.isFinite ? $0 : nil }
    }
}

/// What a `strimr://play/...` link asks of the playback it starts.
nonisolated struct ExternalPlayOptions: Equatable, Sendable {
    /// Seconds to start at. Wins over `resume`.
    var offset: TimeInterval?
    /// false starts from the beginning instead of the saved position, which is what plain play links do.
    var resume = true

    init(query: [String: String]) {
        offset = query["offset"].flatMap(ExternalControlCommand.seconds).flatMap { $0 >= 0 ? $0 : nil }
        resume = switch query["resume"] {
        case "0", "false": false
        default: true
        }
    }
}
