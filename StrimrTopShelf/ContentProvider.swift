import Foundation
import Security
import TVServices

final class ContentProvider: TVTopShelfContentProvider {
    override func loadTopShelfContent() async -> (any TVTopShelfContent)? {
        guard let session = TopShelfSession.load() else { return nil }

        async let continueWatching = (try? fetchHub(path: "/hubs/continueWatching", session: session)) ?? []
        async let promoted = (try? fetchHubs(path: "/hubs/promoted", session: session)) ?? []

        let continueItems = await continueWatching
        let promotedHubs = await promoted
        let recentlyAddedItems = promotedHubs
            .filter { $0.hubIdentifier.localizedCaseInsensitiveContains("recentlyAdded") }
            .flatMap(\.metadata)
        let sections = [
            makeSection(
                title: String(localized: "topshelf.continueWatching"),
                items: continueItems,
                session: session,
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedMovies"),
                items: recentlyAddedItems.filter { $0.type == "movie" },
                session: session,
            ),
            makeSection(
                title: String(localized: "topshelf.recentlyAddedShows"),
                items: recentlyAddedItems.filter { ["show", "season", "episode"].contains($0.type) },
                session: session,
            ),
        ].compactMap(\.self)

        guard !sections.isEmpty else { return nil }
        return TVTopShelfSectionedContent(sections: sections)
    }

    private func fetchHub(path: String, session: TopShelfSession) async throws -> [TopShelfMediaItem] {
        let response: HubContainer = try await request(path: path, session: session)
        return response.mediaContainer.hub?.first?.metadata ?? []
    }

    private func fetchHubs(path: String, session: TopShelfSession) async throws -> [TopShelfHub] {
        let response: HubContainer = try await request(
            path: path,
            queryItems: [
                URLQueryItem(name: "count", value: "20"),
                URLQueryItem(name: "excludeContinueWatching", value: "1"),
                URLQueryItem(name: "includeLibraryPlaylists", value: "0"),
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
        ) else {
            throw TopShelfError.invalidURL
        }
        components.queryItems = queryItems.isEmpty ? nil : queryItems
        guard let url = components.url else { throw TopShelfError.invalidURL }

        var request = URLRequest(url: url)
        request.timeoutInterval = 10
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Strimr", forHTTPHeaderField: "X-Plex-Product")
        request.setValue("tvOS", forHTTPHeaderField: "X-Plex-Platform")
        request.setValue(session.token, forHTTPHeaderField: "X-Plex-Token")
        request.setValue(Locale.preferredLanguages.first ?? "en", forHTTPHeaderField: "X-Plex-Language")

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let response = response as? HTTPURLResponse, 200 ..< 300 ~= response.statusCode else {
            throw TopShelfError.requestFailed
        }
        return try JSONDecoder().decode(Response.self, from: data)
    }

    private func makeSection(
        title: String,
        items: [TopShelfMediaItem],
        session: TopShelfSession,
    ) -> TVTopShelfItemCollection<TVTopShelfSectionedItem>? {
        let topShelfItems = Array(items.prefix(20)).compactMap { makeItem($0, session: session) }
        guard !topShelfItems.isEmpty else { return nil }

        let section = TVTopShelfItemCollection(items: topShelfItems)
        section.title = title
        return section
    }

    private func makeItem(
        _ media: TopShelfMediaItem,
        session: TopShelfSession,
    ) -> TVTopShelfSectionedItem? {
        guard media.isSupported,
              let displayURL = deepLink(action: "media", media: media),
              let playURL = deepLink(action: "play", media: media)
        else {
            return nil
        }

        let item = TVTopShelfSectionedItem(identifier: "\(media.type)-\(media.ratingKey)")
        item.title = media.displayTitle
        item.imageShape = .hdtv
        item.displayAction = TVTopShelfAction(url: displayURL)
        item.playAction = TVTopShelfAction(url: playURL)

        if let artworkPath = media.art ?? media.thumb,
           let imageURL = imageURL(path: artworkPath, session: session)
        {
            item.setImageURL(imageURL, for: .screenScale1x)
            item.setImageURL(imageURL, for: .screenScale2x)
        }
        return item
    }

    private func deepLink(action: String, media: TopShelfMediaItem) -> URL? {
        var components = URLComponents()
        components.scheme = "strimr"
        components.host = action
        components.path = "/\(media.ratingKey)"
        components.queryItems = [URLQueryItem(name: "type", value: media.type)]
        return components.url
    }

    private func imageURL(path: String, session: TopShelfSession) -> URL? {
        var components = URLComponents(
            url: session.serverURL.appendingPathComponent("photo/:/transcode"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: session.token),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: "800"),
            URLQueryItem(name: "height", value: "450"),
            URLQueryItem(name: "minSize", value: "1"),
            URLQueryItem(name: "upscale", value: "1"),
        ]
        return components?.url
    }
}

private struct TopShelfSession {
    private static let appGroup = "group.com.github.wunax.strimr"
    private static let keychainService = "com.github.wunax.strimr.top-shelf"
    private static let tokenKey = "plex.serverToken"
    private static let serverURLKey = "plex.serverURL"

    let serverURL: URL
    let token: String

    static func load() -> TopShelfSession? {
        guard let defaults = UserDefaults(suiteName: appGroup),
              let serverURLString = defaults.string(forKey: serverURLKey),
              let serverURL = URL(string: serverURLString),
              let accessGroup = Bundle.main.object(forInfoDictionaryKey: "TopShelfKeychainAccessGroup") as? String,
              let token = keychainString(accessGroup: accessGroup)
        else {
            return nil
        }
        return TopShelfSession(serverURL: serverURL, token: token)
    }

    private static func keychainString(accessGroup: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: keychainService,
            kSecAttrAccount as String: tokenKey,
            kSecAttrAccessGroup as String: accessGroup,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess,
              let data = item as? Data
        else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}

private struct HubContainer: Decodable {
    struct MediaContainer: Decodable {
        let hub: [TopShelfHub]?

        private enum CodingKeys: String, CodingKey {
            case hub = "Hub"
        }
    }

    let mediaContainer: MediaContainer

    private enum CodingKeys: String, CodingKey {
        case mediaContainer = "MediaContainer"
    }
}

private struct TopShelfHub: Decodable {
    let hubIdentifier: String
    let metadata: [TopShelfMediaItem]

    private enum CodingKeys: String, CodingKey {
        case hubIdentifier
        case metadata = "Metadata"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        hubIdentifier = try container.decode(String.self, forKey: .hubIdentifier)
        metadata = try container.decodeIfPresent([TopShelfMediaItem].self, forKey: .metadata) ?? []
    }
}

private struct TopShelfMediaItem: Decodable {
    let ratingKey: String
    let type: String
    let title: String
    let parentTitle: String?
    let grandparentTitle: String?
    let thumb: String?
    let art: String?

    var isSupported: Bool {
        ["movie", "show", "season", "episode"].contains(type)
    }

    var displayTitle: String {
        switch type {
        case "season":
            guard let parentTitle else { return title }
            return "\(parentTitle) — \(title)"
        case "episode":
            guard let grandparentTitle else { return title }
            return "\(grandparentTitle) — \(title)"
        default:
            return title
        }
    }
}

private enum TopShelfError: Error {
    case invalidURL
    case requestFailed
}
