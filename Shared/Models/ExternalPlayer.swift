import Foundation

nonisolated enum Platform: Sendable {
    case iOS
    case macOS
    case tvOS

    static var current: Platform {
        #if os(tvOS)
            .tvOS
        #elseif os(macOS)
            .macOS
        #else
            .iOS
        #endif
    }
}

nonisolated enum ExternalPlayerID: String, Codable, CaseIterable, Identifiable, Sendable {
    case infuse
    case vlc
    case iina
    case nativePlayer

    enum LaunchStrategy: Equatable {
        case template(String)
        /// macOS: the stream URL is opened in the app with this bundle id.
        case application(bundleID: String)
    }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .infuse: "Infuse"
        case .vlc: "VLC"
        case .iina: "IINA"
        case .nativePlayer: "Native Player"
        }
    }

    func isSupported(on platform: Platform) -> Bool {
        launchStrategy(on: platform) != nil
    }

    func launchStrategy(on platform: Platform) -> LaunchStrategy? {
        switch (self, platform) {
        case (.infuse, _):
            .template("infuse://x-callback-url/play?url={url}&x-success={callback}&x-error={callback}")
        case (.vlc, .macOS):
            .application(bundleID: "org.videolan.vlc")
        case (.vlc, .iOS), (.vlc, .tvOS):
            .template("vlc-x-callback://x-callback-url/stream?url={url}&x-success={callback}")
        case (.iina, .macOS):
            .template("iina://weblink?url={url}")
        case (.nativePlayer, .tvOS):
            .template(
                "nativeplayer://x-callback-url/play?url={url}&filename={title}&position={position}&sub={subtitles}&x-success={callback}&x-error={callback}",
            )
        case (.iina, _), (.nativePlayer, _):
            nil
        }
    }

    /// URL scheme of a template player, used to check whether the app is installed.
    func scheme(on platform: Platform) -> String? {
        guard case let .template(template) = launchStrategy(on: platform),
              let separator = template.range(of: "://")
        else { return nil }
        return String(template[..<separator.lowerBound])
    }
}

nonisolated struct CustomExternalPlayer: Codable, Equatable, Sendable {
    var name: String
    var template: String

    var isValid: Bool {
        guard !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return false }
        return (try? ExternalPlayerTemplate.validate(template)) != nil
    }
}

nonisolated enum ExternalPlayerSelection: Codable, Equatable, Hashable, Sendable {
    case known(ExternalPlayerID)
    case custom
}

nonisolated struct ExternalPlaybackTarget: Equatable, Sendable {
    let url: URL
    let title: String
    let item: MediaIdentity
    let duration: TimeInterval?
    var startPosition: TimeInterval = 0
    /// SRT files beside the video, best match first.
    var subtitles: [URL] = []
}

extension ExternalPlaybackTarget {
    init(url: URL, media: MediaItem) {
        self.init(url: url, title: Self.title(for: media), item: media.identity, duration: media.duration)
    }

    /// "Series — S01E02 — Title" for an episode, the item title otherwise.
    static func title(for media: MediaItem) -> String {
        guard media.type == .episode else { return media.title }
        var components: [String] = []
        if let series = media.grandparentTitle, !series.isEmpty {
            components.append(series)
        }
        if let season = media.parentIndex, let episode = media.index {
            components.append(String(format: "S%02dE%02d", season, episode))
        }
        components.append(media.title)
        return components.joined(separator: " — ")
    }
}

nonisolated enum ExternalLaunchRequest: Equatable, Sendable {
    /// URL with the player's scheme, built from a template.
    case url(URL)
    /// macOS: the stream URL opened in the app with this bundle id.
    case open(URL, bundleID: String)
}

/// The player chosen in the settings, resolved with the custom player definition.
nonisolated enum ExternalPlayer: Equatable, Sendable {
    case known(ExternalPlayerID)
    case custom(CustomExternalPlayer)

    /// Nil means the built-in player, including a custom selection without a valid definition.
    init?(selection: ExternalPlayerSelection?, custom: CustomExternalPlayer?) {
        switch selection {
        case let .known(id):
            self = .known(id)
        case .custom:
            guard let custom, custom.isValid else { return nil }
            self = .custom(custom)
        case nil:
            return nil
        }
    }

    var displayName: String {
        switch self {
        case let .known(id): id.displayName
        case let .custom(player): player.name
        }
    }

    func isSupported(on platform: Platform) -> Bool {
        switch self {
        case let .known(id): id.isSupported(on: platform)
        case .custom: true
        }
    }

    func launchRequest(for target: ExternalPlaybackTarget, platform: Platform) -> ExternalLaunchRequest? {
        let template: String
        switch self {
        case let .known(id):
            switch id.launchStrategy(on: platform) {
            case let .template(value):
                template = value
            case let .application(bundleID):
                return .open(target.url, bundleID: bundleID)
            case nil:
                return nil
            }
        case let .custom(player):
            template = player.template
        }
        guard let url = try? ExternalPlayerTemplate.render(template, target: target) else {
            return nil
        }
        return .url(url)
    }
}

nonisolated enum ExternalPlaybackError: Error, Equatable {
    case noPlayableSource
}
