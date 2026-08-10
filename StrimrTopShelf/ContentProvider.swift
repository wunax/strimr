import Foundation
import Security
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let session = TopShelfSession.load() else { return nil }
        let sections: [TVTopShelfItemCollection<TVTopShelfSectionedItem>]
        switch session.provider {
        case .plex:
            sections = await plexSections(session: session)
        case .jellyfin:
            sections = await jellyfinSections(session: session)
        }
        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private func plexSections(session: TopShelfSession) async -> [TVTopShelfItemCollection<TVTopShelfSectionedItem>] {
        async let continueWatching = (try? fetchPlexHub(path: "/hubs/continueWatching", session: session)) ?? []
        async let promoted = (try? fetchPlexHubs(path: "/hubs/promoted", session: session)) ?? []
        let continueItems = await continueWatching.map(TopShelfDisplayItem.init)
        let recentlyAdded = await promoted
            .filter { $0.hubIdentifier.localizedCaseInsensitiveContains("recentlyAdded") }
            .flatMap(\.metadata)
            .map(TopShelfDisplayItem.init)
        return [
            makeSection(title: String(localized: "topshelf.continueWatching"), items: continueItems, session: session),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedMovies"),
                items: recentlyAdded.filter { $0.type == "movie" },
                session: session
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedShows"),
                items: recentlyAdded.filter { ["show", "season", "episode"].contains($0.type) },
                session: session
            ),
        ].compactMap(\.self)
    }

    private func jellyfinSections(session: TopShelfSession) async -> [TVTopShelfItemCollection<TVTopShelfSectionedItem>] {
        guard let userID = session.userID else { return [] }
        async let resume: JellyfinItemsResponse? = try? request(
            path: "/UserItems/Resume",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie,Episode"),
                URLQueryItem(name: "Limit", value: "20"),
                URLQueryItem(name: "Fields", value: "Overview,UserData,SeriesName,ParentIndexNumber,IndexNumber"),
            ],
            session: session
        )
        async let latestMovies: [JellyfinTopShelfItem]? = try? request(
            path: "/Items/Latest",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Movie"),
                URLQueryItem(name: "Limit", value: "20"),
            ],
            session: session
        )
        async let latestShows: [JellyfinTopShelfItem]? = try? request(
            path: "/Items/Latest",
            queryItems: [
                URLQueryItem(name: "UserId", value: userID),
                URLQueryItem(name: "IncludeItemTypes", value: "Series,Episode"),
                URLQueryItem(name: "Limit", value: "20"),
            ],
            session: session
        )
        return [
            makeSection(
                title: String(localized: "topshelf.continueWatching"),
                items: await (resume?.items ?? []).map(TopShelfDisplayItem.init),
                session: session
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedMovies"),
                items: await (latestMovies ?? []).map(TopShelfDisplayItem.init),
                session: session
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedShows"),
                items: await (latestShows ?? []).map(TopShelfDisplayItem.init),
                session: session
            ),
        ].compactMap(\.self)
    }

    private func fetchPlexHub(path: String, session: TopShelfSession) async throws -> [PlexTopShelfItem] {
        let response: PlexHubContainer = try await request(path: path, session: session)
        return response.mediaContainer.hub?.first?.metadata ?? []
    }

    private func fetchPlexHubs(path: String, session: TopShelfSession) async throws -> [PlexTopShelfHub] {
        let response: PlexHubContainer = try await request(
            path: path,
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeContinueWatching", value: "1"),
                URLQueryItem(name: "includeLibraryPlaylists", value: "0"),
            ],
            session: session
        )
        return response.mediaContainer.hub ?? []
    }

    private func request<Response: Decodable>(
        path: String,
        queryItems: [URLQueryItem] = [],
        session: TopShelfSession
    ) async throws -> Response {
        guard var components = URLComponents(
            url: session.serverURL.appendingPathComponent(path),
            resolvingAgainstBaseURL: false
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
                forHTTPHeaderField: "Authorization"
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
        session: TopShelfSession
    ) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let values = Array(items.prefix(20)).compactMap { makeItem($0, session: session) }
        guard !values.isEmpty else { return nil }
        let section = TVTopShelfItemCollection(items: values)
        section.title = title
        return section
    }

    private func makeItem(_ media: TopShelfDisplayItem, session: TopShelfSession) -> TVTopShelfSectionedItem? {
        guard let displayURL = deepLink(action: "media", media: media, session: session),
              let playURL = deepLink(action: "play", media: media, session: session)
        else { return nil }
        let item = TVTopShelfSectionedItem(identifier: "\(session.provider.rawValue)-\(media.type)-\(media.id)")
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
                      resolvingAgainstBaseURL: false
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
                resolvingAgainstBaseURL: false
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

private struct TopShelfSession {
    private static let appGroup = "group.com.github.wunax.strimr"
    private static let keychainService = "com.github.wunax.strimr.top-shelf"
    private static let sessionKey = "media.session.v1"
    private static let tokenKey = "media.serverToken"
    // Kept for upgrades from the Plex-only format; remove after a future migration window.
    private static let legacyTokenKey = "plex.serverToken"
    private static let legacyURLKey = "plex.serverURL"

    struct StoredSession: Codable {
        let provider: TopShelfProvider
        let serverURL: URL
        let serverID: String
        let userID: String?
    }

    let provider: TopShelfProvider
    let serverURL: URL
    let serverID: String
    let userID: String?
    let token: String

    static func load() -> TopShelfSession? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String
        else { return nil }
        if let data = defaults.data(forKey: sessionKey),
           let stored = try? JSONDecoder().decode(StoredSession.self, from: data),
           let token = keychainString(key: tokenKey, accessGroup: accessGroup)
        {
            return TopShelfSession(
                provider: stored.provider,
                serverURL: stored.serverURL,
                serverID: stored.serverID,
                userID: stored.userID,
                token: token
            )
        }
        guard let value = defaults.string(forKey: legacyURLKey),
              let url = URL(string: value),
              let token = keychainString(key: legacyTokenKey, accessGroup: accessGroup)
        else { return nil }
        return TopShelfSession(provider: .plex, serverURL: url, serverID: "plex", userID: nil, token: token)
    }

    private static func keychainString(key: String, accessGroup: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
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

    init(_ item: PlexTopShelfItem) {
        id = item.ratingKey
        type = item.type
        title = item.title
        parentTitle = item.parentTitle
        grandparentTitle = item.grandparentTitle
        artworkPath = item.art ?? item.thumb
        primaryTag = nil
        backdropTag = nil
    }

    init(_ item: JellyfinTopShelfItem) {
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
    }

    var displayTitle: String {
        if type == "episode", let grandparentTitle { return "\(grandparentTitle) — \(title)" }
        if type == "season", let parentTitle { return "\(parentTitle) — \(title)" }
        return title
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
    let ratingKey: String
    let type: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let thumb: String?
    let art: String?
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
    let id: String
    let name: String
    let type: String
    let seriesName: String?
    let seasonName: String?
    let imageTags: [String: String]?
    let backdropImageTags: [String]?
    private enum CodingKeys: String, CodingKey {
        case id = "Id"; case name = "Name"; case type = "Type"
        case seriesName = "SeriesName"; case seasonName = "SeasonName"
        case imageTags = "ImageTags"; case backdropImageTags = "BackdropImageTags"
    }
}

private enum TopShelfError: Error { case invalidURL, requestFailed }
