import Foundation
import Security
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    private struct ServerRows {
        var continueWatching: [TopShelfDisplayItem] = []
        var recentMovies: [TopShelfDisplayItem] = []
        var recentShows: [TopShelfDisplayItem] = []
    }

    /// Queries every server of the active profile in parallel; a server that fails is left out.
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        let sessions = TopShelfSession.loadAll()
        guard !sessions.isEmpty else { return nil }
        let rows = await withTaskGroup(of: ServerRows.self) { group in
            for session in sessions {
                group.addTask {
                    switch session.provider {
                    case .plex:
                        await self.plexRows(session: session)
                    case .jellyfin:
                        await self.jellyfinRows(session: session)
                    }
                }
            }
            var rows: [ServerRows] = []
            for await row in group {
                rows.append(row)
            }
            return rows
        }
        let sections = [
            makeSection(
                title: String(localized: "topshelf.continueWatching"),
                items: merge(rows.map(\.continueWatching), date: \.lastViewedAt),
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedMovies"),
                items: merge(rows.map(\.recentMovies), date: \.addedAt),
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedShows"),
                items: merge(rows.map(\.recentShows), date: \.addedAt),
            ),
        ].compactMap(\.self)
        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private func merge(_ rows: [[TopShelfDisplayItem]], date: (TopShelfDisplayItem) -> Date?) -> [TopShelfDisplayItem] {
        TopShelfSessions.merge(rows, date: date, descriptor: \.matchDescriptor)
    }

    private func plexRows(session: TopShelfSession) async -> ServerRows {
        async let continueWatching = (try? fetchPlexHub(path: "/hubs/continueWatching", session: session)) ?? []
        async let promoted = (try? fetchPlexHubs(path: "/hubs/promoted", session: session)) ?? []
        let continueItems = await continueWatching.map { TopShelfDisplayItem($0, session: session) }
        let recentlyAdded = await promoted
            .filter { $0.hubIdentifier.localizedCaseInsensitiveContains("recentlyAdded") }
            .flatMap(\.metadata)
            .map { TopShelfDisplayItem($0, session: session) }
        return ServerRows(
            continueWatching: continueItems,
            recentMovies: recentlyAdded.filter { $0.type == "movie" },
            recentShows: recentlyAdded.filter { ["show", "season", "episode"].contains($0.type) },
        )
    }

    private func jellyfinRows(session: TopShelfSession) async -> ServerRows {
        guard let userID = session.userID else { return ServerRows() }
        let fields = "Overview,UserData,SeriesName,ParentIndexNumber,IndexNumber,ProviderIds,DateCreated"
        async let resume: JellyfinItemsResponse? = try? request(
            path: "/UserItems/Resume",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "Fields", value: fields),
            ],
            session: session,
        )
        async let latestMovies: [JellyfinTopShelfItem]? = try? request(
            path: "/Items/Latest",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "Fields", value: fields),
            ],
            session: session,
        )
        async let latestShows: [JellyfinTopShelfItem]? = try? request(
            path: "/Items/Latest",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Series,Episode"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "Fields", value: fields),
            ],
            session: session,
        )
        return await ServerRows(
            continueWatching: (resume?.items ?? []).map { TopShelfDisplayItem($0, session: session) },
            recentMovies: (latestMovies ?? []).map { TopShelfDisplayItem($0, session: session) },
            recentShows: (latestShows ?? []).map { TopShelfDisplayItem($0, session: session) },
        )
    }

    private func fetchPlexHub(path: String, session: TopShelfSession) async throws -> [PlexTopShelfItem] {
        let response: PlexHubContainer = try await request(
            path: path,
            queryItems: [URLQueryItem(name: "includeGuids", value: "1")],
            session: session,
        )
        return response.mediaContainer.hub?.first?.metadata ?? []
    }

    private func fetchPlexHubs(path: String, session: TopShelfSession) async throws -> [PlexTopShelfHub] {
        let response: PlexHubContainer = try await request(
            path: path,
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeContinueWatching", value: "1"),
                URLQueryItem(name: "includeLibraryPlaylists", value: "0"),
                URLQueryItem(name: "includeGuids", value: "1"),
            ],
            session: session,
        )
        return response.mediaContainer.hub ?? []
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        session: TopShelfSession,
    ) async throws -> Response {
        guard var components = URLComponents(
            url: session.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false,
        ) else { throw TopShelfError.invalidURL }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw TopShelfError.invalidURL }
        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        switch session.provider {
        case .plex:
            request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
            request.setValue("tvOS", forHTTPHeaderField: "X-Plex-Platform")
            request.setValue(session.token, forHTTPHeaderField: "X-Plex-Token")
            request.setValue(Locale.preferredLanguages.first ?? "en", forHTTPHeaderField: "X-Plex-Language")
        case .jellyfin:
            request.setValue(
                "MediaBrowser Client=\"Strimr\", Device=\"Apple TV\", DeviceId=\"TopShelf\", Version=\"1\", Token=\"\(session.token)\"",
                forHTTPHeaderField: "Authorization",
            )
            request.setValue(session.token, forHTTPHeaderField: "X-Emby-Token")
        }
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200 ..< 300 ~= response.statusCode else {
            throw TopShelfError.requestFailed
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeSection(
        title: String,
        items: [TopShelfDisplayItem],
    ) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let values = Array(items.prefix(20)).compactMap { makeItem($0, session: $0.session) }
        guard !values.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: values)
        section.title = title
        return section
    }

    private func makeItem(_ media: TopShelfDisplayItem, session: TopShelfSession) -> TVTopShelfSectionedItem? {
        guard let displayURL = deepLink(action: "media", media: media, session: session),
              let playURL = deepLink(action: "play", media: media, session: session)
        else { return nil }
        let item = TVTopShelfSectionedItem(
            identifier: "\(session.provider.rawValue)-\(session.serverID)-\(media.type)-\(media.id)",
        )
        item.title = media.displayTitle
        item.imageShape = .hdtv
        item.displayAction = TVTopShelfAction(url: displayURL)
        item.playAction = TVTopShelfAction(url: playURL)
        if let imageURL = imageURL(media: media, session: session) {
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
        }
        return item
    }

    private func deepLink(action: String, media: TopShelfDisplayItem, session: TopShelfSession) -> URL? {
        var components = URLComponents()
        components.scheme = "strimr"
        components.host = action
        components.path = "/\(media.id)"
        components.queryItems = [
            URLQueryItem(name: "provider", value: session.provider.rawValue),
            URLQueryItem(name: "server", value: session.serverID),
            URLQueryItem(name: "type", value: media.type),
        ]
        return components.url
    }

    private func imageURL(media: TopShelfDisplayItem, session: TopShelfSession) -> URL? {
        switch session.provider {
        case .plex:
            guard let path = media.artworkPath,
                  var components = URLComponents(
                      url: session.serverURL.appendingPathComponent("photo/:/transcode"),
                      resolvingAgainstBaseURL: false,
                  )
            else { return nil }
            components.queryItems = [
                URLQueryItem(name: "X-Plex-Token", value: session.token),
                URLQueryItem(name: "url", value: path),
                URLQueryItem(name: "width", value: "800"),
                URLQueryItem(name: "height", value: "450"),
                URLQueryItem(name: "minSize", value: "1"),
                URLQueryItem(name: "upscale", value: "1"),
            ]
            return components.url
        case .jellyfin:
            let imageType = media.backdropTag == nil ? "Primary" : "Backdrop"
            guard var components = URLComponents(
                url: session.serverURL
                    .appendingPathComponent("Items")
                    .appendingPathComponent(media.id)
                    .appendingPathComponent("Images")
                    .appendingPathComponent(imageType),
                resolvingAgainstBaseURL: false,
            ) else { return nil }
            components.queryItems = [
                URLQueryItem(name: "tag", value: media.backdropTag ?? media.primaryTag),
                URLQueryItem(name: "maxWidth", value: "800"),
                URLQueryItem(name: "maxHeight", value: "450"),
                URLQueryItem(name: "quality", value: "90"),
                URLQueryItem(name: "api_key", value: session.token),
            ].filter { $0.value != nil }
            return components.url
        }
    }
}

private enum TopShelfProvider: String, Codable { case plex, jellyfin }

private struct TopShelfSession: Sendable {
    let provider: TopShelfProvider
    let serverURL: URL
    let serverID: String
    let userID: String?
    let token: String

    /// Servers shared by the app; also reads the single-session formats of previous versions.
    static func loadAll() -> [TopShelfSession] {
        guard let defaults = UserDefaults(suiteName: TopShelfSessions.appGroup),
              let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String
        else { return [] }
        let stored = TopShelfSessions.decode(
            v2: defaults.data(forKey: TopShelfSessions.sessionsKey),
            v1: defaults.data(forKey: TopShelfSessions.legacySessionKey),
        )
        let sessions = stored.sessions.compactMap { session -> TopShelfSession? in
            let tokenKey = stored.legacyTokenKeys[session.tokenKey] ?? session.tokenKey
            guard let provider = TopShelfProvider(rawValue: session.provider),
                  let token = keychainString(key: tokenKey, accessGroup: accessGroup)
            else { return nil }
            return TopShelfSession(
                provider: provider,
                serverURL: session.serverURL,
                serverID: session.serverID,
                userID: session.userID,
                token: token,
            )
        }
        if !sessions.isEmpty {
            return sessions
        }
        guard let value = defaults.string(forKey: TopShelfSessions.legacyPlexURLKey),
              let url = URL(string: value),
              let token = keychainString(key: TopShelfSessions.legacyPlexTokenKey, accessGroup: accessGroup)
        else { return [] }
        return [TopShelfSession(provider: .plex, serverURL: url, serverID: "plex", userID: nil, token: token)]
    }

    private static func keychainString(key: String, accessGroup: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: TopShelfSessions.keychainService,
            kSecAttrAccount as String: key,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

private struct TopShelfDisplayItem {
    let id: String
    let type: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let artworkPath: String?
    let primaryTag: String?
    let backdropTag: String?
    let session: TopShelfSession
    let matchDescriptor: MediaMatchDescriptor
    let lastViewedAt: Date?
    let addedAt: Date?

    init(_ item: PlexTopShelfItem, session: TopShelfSession) {
        id = item.ratingKey
        type = item.type
        title = item.title
        parentTitle = item.parentTitle
        grandparentTitle = item.grandparentTitle
        artworkPath = item.art ?? item.thumb
        primaryTag = nil
        backdropTag = nil
        self.session = session
        matchDescriptor = MediaMatchDescriptor(
            kind: Self.matchKind(item.type),
            guid: item.guid,
            externalIDs: ExternalIDs(plexGuids: item.guids?.map(\.id) ?? []),
            seasonNumber: item.parentIndex,
            episodeNumber: item.index,
        )
        lastViewedAt = item.lastViewedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
        addedAt = item.addedAt.map { Date(timeIntervalSince1970: TimeInterval($0)) }
    }

    init(_ item: JellyfinTopShelfItem, session: TopShelfSession) {
        id = item.id
        type = switch item.type.lowercased() {
        case "series": "show"
        default: item.type.lowercased()
        }
        title = item.name
        parentTitle = item.seasonName
        grandparentTitle = item.seriesName
        artworkPath = nil
        primaryTag = item.imageTags?["Primary"]
        backdropTag = item.backdropImageTags?.first
        self.session = session
        matchDescriptor = MediaMatchDescriptor(
            kind: Self.matchKind(type),
            guid: nil,
            externalIDs: ExternalIDs(providerIDs: item.providerIDs ?? [:]),
            seasonNumber: item.parentIndexNumber,
            episodeNumber: item.indexNumber,
        )
        lastViewedAt = item.userData?.lastPlayedDate.flatMap(Self.date)
        addedAt = item.dateCreated.flatMap(Self.date)
    }

    var displayTitle: String {
        if type == "episode", let grandparentTitle {
            return "\(grandparentTitle) — \(title)"
        }
        if type == "season", let parentTitle {
            return "\(parentTitle) — \(title)"
        }
        return title
    }

    private static func matchKind(_ type: String) -> MediaMatchDescriptor.Kind {
        switch type.lowercased() {
        case "movie": .movie
        case "show", "series": .series
        case "season": .season
        case "episode": .episode
        default: .other
        }
    }

    private static func date(_ value: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: value) {
            return date
        }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: value)
    }
}

private struct PlexHubContainer: Decodable {
    struct MediaContainer: Decodable {
        let hub: [PlexTopShelfHub]?
        private enum CodingKeys: String, CodingKey { case hub = "Hub" }
    }

    let mediaContainer: MediaContainer
    private enum CodingKeys: String, CodingKey { case mediaContainer = "MediaContainer" }
}

private struct PlexTopShelfHub: Decodable {
    let hubIdentifier: String
    let metadata: [PlexTopShelfItem]
    private enum CodingKeys: String, CodingKey { case hubIdentifier; case metadata = "Metadata" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hubIdentifier = try container.decode(String.self, forKey: .hubIdentifier)
        metadata = try container.decodeIfPresent([PlexTopShelfItem].self, forKey: .metadata) ?? []
    }
}

private struct PlexTopShelfItem: Decodable {
    struct Guid: Decodable {
        let id: String
    }

    let ratingKey: String
    let type: String
    let title: String
    let guid: String?
    let parentTitle: String?
    let grandparentTitle: String?
    let parentIndex: Int?
    let index: Int?
    let thumb: String?
    let art: String?
    let lastViewedAt: Int?
    let addedAt: Int?
    let guids: [Guid]?

    private enum CodingKeys: String, CodingKey {
        case ratingKey, type, title, guid, parentTitle, grandparentTitle, parentIndex, index, thumb, art
        case lastViewedAt, addedAt
        case guids = "Guid"
    }
}

private struct JellyfinItemsResponse: Decodable {
    let items: [JellyfinTopShelfItem]
    private enum CodingKeys: String, CodingKey { case items = "Items" }
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        items = try container.decodeIfPresent([JellyfinTopShelfItem].self, forKey: .items) ?? []
    }
}

private struct JellyfinTopShelfItem: Decodable {
    struct UserData: Decodable {
        let lastPlayedDate: String?
        private enum CodingKeys: String, CodingKey { case lastPlayedDate = "LastPlayedDate" }
    }

    let id: String
    let name: String
    let type: String
    let seriesName: String?
    let seasonName: String?
    let parentIndexNumber: Int?
    let indexNumber: Int?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    let providerIDs: [String: String]?
    let dateCreated: String?
    let userData: UserData?
    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"; case type = "Type"
        case seriesName = "SeriesName"; case seasonName = "SeasonName"
        case parentIndexNumber = "ParentIndexNumber"; case indexNumber = "IndexNumber"
        case imageTags = "ImageTags"; case backdropImageTags = "BackdropImageTags"
        case providerIDs = "ProviderIds"; case dateCreated = "DateCreated"; case userData = "UserData"
    }
}

private enum TopShelfError: Error { case invalidURL, requestFailed }
