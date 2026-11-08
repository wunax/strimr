import Foundation

nonisolated enum TrackerService: String, Codable, CaseIterable, Identifiable, Sendable {
    case trakt
    case simkl

    /// Trakt is hidden until its API app is approved for production.
    static let available: [TrackerService] = allCases.filter { $0 != .trakt }

    var id: String {
        rawValue
    }

    var displayName: String {
        switch self {
        case .trakt: "Trakt"
        case .simkl: "Simkl"
        }
    }

    var websiteURL: URL {
        switch self {
        case .trakt: URL(string: "https://trakt.tv")!
        case .simkl: URL(string: "https://simkl.com")!
        }
    }
}

/// What a tracker needs to recognize a title. For an episode, `ids` are the series' ids: trackers address episodes
/// by series, season and number, and many episodes have no external id of their own.
nonisolated struct TrackerItem: Codable, Hashable, Sendable {
    enum Kind: String, Codable, Sendable {
        case movie
        case episode
    }

    let kind: Kind
    let ids: ExternalIDs
    let title: String?
    let year: Int?
    let season: Int?
    let episode: Int?

    init(
        kind: Kind,
        ids: ExternalIDs,
        title: String? = nil,
        year: Int? = nil,
        season: Int? = nil,
        episode: Int? = nil,
    ) {
        self.kind = kind
        self.ids = ids
        self.title = title
        self.year = year
        self.season = season
        self.episode = episode
    }

    /// Identifies the remote row a write changes, so queued writes about the same row can be merged.
    var rowKey: String {
        let id = ids.imdb.map { "imdb:\($0)" }
            ?? ids.tmdb.map { "tmdb:\($0)" }
            ?? ids.tvdb.map { "tvdb:\($0)" }
            ?? "none"
        return [kind.rawValue, id, season.map(String.init) ?? "", episode.map(String.init) ?? ""]
            .joined(separator: "|")
    }
}

nonisolated enum TrackerPlaybackEvent: String, Sendable {
    case start
    case pause
    case stop
}

nonisolated struct TrackerPlaybackPolicy: Sendable {
    /// Minimum gap before the same state is reported again, to keep a pause/play storm from becoming a write burst.
    let resendThrottle: TimeInterval
    /// A `stop` from this progress upwards records a watch on the service.
    let watchedProgress: Double
}

nonisolated struct TrackerHistoryEntry: Hashable, Sendable {
    let item: TrackerItem
    let watchedAt: Date?
}

nonisolated struct TrackerSession: Codable, Equatable, Sendable {
    var accessToken: String
    var refreshToken: String
    var expiresAt: Date
}

/// OAuth token answer shared by both services.
nonisolated struct TrackerTokenResponse: Decodable, Sendable {
    let accessToken: String
    let refreshToken: String?
    let expiresIn: TimeInterval?
    let scope: String?

    private enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case refreshToken = "refresh_token"
        case expiresIn = "expires_in"
        case scope
    }

    func session(now: Date, keepingRefreshToken previous: String? = nil) -> TrackerSession? {
        guard let refreshToken = refreshToken.flatMap({ $0.isEmpty ? nil : $0 }) ?? previous else { return nil }
        let lifetime = expiresIn ?? 7 * 24 * 60 * 60
        return TrackerSession(
            accessToken: accessToken,
            refreshToken: refreshToken,
            expiresAt: now.addingTimeInterval(lifetime),
        )
    }
}

nonisolated enum TrackerAPIError: Error, Equatable {
    case unauthorized
    /// The grant is gone: the user has to authorize the app again.
    case sessionExpired
    case notFound
    case conflict
    case rateLimited(retryAfter: TimeInterval?)
    /// Simkl's short per-user write lock.
    case writeLocked
    /// Simkl's block after repeated overages.
    case throttled
    /// Trakt's account limit or VIP-only answers, which retrying cannot resolve.
    case accountLimit
    case accountLocked
    case server(status: Int)
    case unexpected(status: Int)
    case invalidResponse
    /// The service asked for quiet, or the account is gone: nothing was sent.
    case unavailable
}

nonisolated enum TrackerIssue: String, Codable, Sendable {
    case accountLimit
    case accountLocked
}

nonisolated struct TrackerUser: Equatable, Sendable {
    let username: String?
}

@MainActor
protocol TrackerClient: AnyObject {
    var service: TrackerService { get }
    var policy: TrackerPlaybackPolicy { get }
    func currentUser() async throws -> TrackerUser
    func report(_ event: TrackerPlaybackEvent, item: TrackerItem, progress: Double) async throws
    func addToHistory(_ entries: [TrackerHistoryEntry]) async throws
    func removeFromHistory(_ items: [TrackerItem]) async throws
    func revoke() async
}

extension Double {
    /// Both services accept two decimals on `progress`, Simkl rejects more.
    nonisolated var trackerProgress: Double {
        (min(max(self, 0), 100) * 100).rounded() / 100
    }
}
