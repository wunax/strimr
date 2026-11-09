import Foundation
@testable import Strimr

@MainActor
final class FakeTrackerClient: TrackerClient {
    struct Report: Equatable {
        let event: TrackerPlaybackEvent
        let item: TrackerItem
        let progress: Double
    }

    let service: TrackerService
    let policy: TrackerPlaybackPolicy
    var reports: [Report] = []
    var added: [[TrackerHistoryEntry]] = []
    var removed: [[TrackerItem]] = []
    var reportFailures: [Error] = []
    var historyFailures: [Error] = []
    var username: String? = "alice"
    var revokeCount = 0

    init(service: TrackerService = .trakt, resendThrottle: TimeInterval = 30) {
        self.service = service
        policy = TrackerPlaybackPolicy(resendThrottle: resendThrottle, watchedProgress: 80)
    }

    func currentUser() async throws -> TrackerUser {
        TrackerUser(username: username)
    }

    func report(_ event: TrackerPlaybackEvent, item: TrackerItem, progress: Double) async throws {
        if !reportFailures.isEmpty {
            throw reportFailures.removeFirst()
        }
        reports.append(Report(event: event, item: item, progress: progress))
    }

    func addToHistory(_ entries: [TrackerHistoryEntry]) async throws {
        if !historyFailures.isEmpty {
            throw historyFailures.removeFirst()
        }
        added.append(entries)
    }

    func removeFromHistory(_ items: [TrackerItem]) async throws {
        if !historyFailures.isEmpty {
            throw historyFailures.removeFirst()
        }
        removed.append(items)
    }

    func revoke() async {
        revokeCount += 1
    }
}

final class FakeTrackerDetailService: FakeMediaService {
    var items: [String: MediaItem] = [:]
    var seasonsByID: [String: [MediaItem]] = [:]
    var episodesByID: [String: [MediaItem]] = [:]
    var library: String?
    var itemRequests: [String] = []
    var failure: Error?

    override func mediaItem(id: String) async throws -> MediaItem {
        itemRequests.append(id)
        if let failure {
            throw failure
        }
        guard let item = items[id] else { throw NotStubbed(function: #function) }
        return item
    }

    override func libraryID(for _: MediaItem) async throws -> String? {
        library
    }

    override func seasons(for media: MediaItem) async throws -> [MediaItem] {
        seasonsByID[media.id] ?? []
    }

    override func episodes(for season: MediaItem, seriesID _: String?) async throws -> [MediaItem] {
        episodesByID[season.id] ?? []
    }
}

enum TrackerFixtures {
    static let server = ServerIdentity(provider: .plex, id: "server")
    static let session = TrackerSession(
        accessToken: "access",
        refreshToken: "refresh",
        expiresAt: Date(timeIntervalSince1970: 2_000_000_000),
    )
    static let movieIDs = ExternalIDs(imdb: "tt0000001", tmdb: "101")
    static let seriesIDs = ExternalIDs(imdb: "tt0000002", tmdb: "202", tvdb: "303")
    static let movie = TrackerItem(kind: .movie, ids: movieIDs, title: "Movie", year: 2020)

    static func episode(_ number: Int, season: Int = 1) -> TrackerItem {
        TrackerItem(kind: .episode, ids: seriesIDs, title: "Series", year: 2019, season: season, episode: number)
    }

    static func movieItem(id: String = "movie", ids: ExternalIDs = movieIDs) -> MediaItem {
        .make(id: id, server: server, title: "Movie", type: .movie, externalIDs: ids, year: 2020)
    }

    static func seriesItem(id: String = "series", ids: ExternalIDs = seriesIDs) -> MediaItem {
        .make(id: id, server: server, title: "Series", type: .series, externalIDs: ids, year: 2019)
    }

    static func episodeItem(id: String = "episode", number: Int = 1, seriesID: String? = "series") -> MediaItem {
        .make(
            id: id,
            server: server,
            title: "Episode",
            type: .episode,
            seasonNumber: 1,
            episodeNumber: number,
            seriesID: seriesID,
        )
    }
}

extension URLRequest {
    var jsonBody: [String: Any]? {
        httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
    }

    var formBody: [String: String] {
        guard let body = httpBody.flatMap({ String(data: $0, encoding: .utf8) }) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = body
        return Dictionary(uniqueKeysWithValues: (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })
    }
}
