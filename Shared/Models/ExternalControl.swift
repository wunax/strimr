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
    case audio(language: String)
    case subs(ExternalSubtitleRequest)

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
        case "audio":
            guard let language = ExternalControlCommand.languageCode(query["lang"]) else { return nil }
            self = .audio(language: language)
        case "subs":
            guard let request = query["lang"].flatMap(ExternalSubtitleRequest.init) else { return nil }
            self = .subs(request)
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

    /// A lowercased language code from a link value, nil when it is empty.
    static func languageCode(_ value: String?) -> String? {
        guard let code = value?.trimmingCharacters(in: .whitespaces).lowercased(), !code.isEmpty else { return nil }
        return code
    }

    /// Rejects `nan` and `inf`, which `Double` would parse.
    static func seconds(_ value: String) -> TimeInterval? {
        Double(value).flatMap { $0.isFinite ? $0 : nil }
    }
}

/// A subtitle language, or no subtitles, asked for by a link.
nonisolated enum ExternalSubtitleRequest: Equatable, Sendable {
    case off
    /// A lowercased ISO 639-1 or 639-2 code, as written in the link.
    case language(String)

    init?(_ value: String) {
        guard let code = ExternalControlCommand.languageCode(value) else { return nil }
        self = code == "off" ? .off : .language(code)
    }
}

/// What a `strimr://play/...` link asks of the playback it starts.
nonisolated struct ExternalPlayOptions: Equatable, Sendable {
    /// Seconds to start at. Wins over `resume`.
    var offset: TimeInterval?
    /// false starts from the beginning. Like the Play button, links resume from the saved position by default.
    var resume = true
    /// For a collection, show or season: queue its items in random order.
    var shuffle = false
    var audio: String?
    var subs: ExternalSubtitleRequest?

    init(query: [String: String]) {
        offset = query["offset"].flatMap(ExternalControlCommand.seconds).flatMap { $0 >= 0 ? $0 : nil }
        resume = switch query["resume"] {
        case "0", "false": false
        default: true
        }
        shuffle = query["shuffle"] == "1" || query["shuffle"] == "true"
        audio = ExternalControlCommand.languageCode(query["audio"])
        subs = query["subs"].flatMap(ExternalSubtitleRequest.init)
    }
}
