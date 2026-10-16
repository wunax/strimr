import Foundation

final class MediaRepository {
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        _ = try context.serverAccessSnapshot()
        self.context = context
    }

    func mediaURL(path: String) -> URL? {
        guard let snapshot = try? context?.serverAccessSnapshot() else { return nil }
        return Self.mediaURL(path: path, baseURL: snapshot.baseURL, token: snapshot.authToken)
    }

    static func mediaURL(path: String, baseURL: URL, token: String) -> URL? {
        let pathAndQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(pathAndQuery[0])
        let normalizedPath = pathOnly.hasPrefix("/") ? pathOnly : "/\(pathOnly)"
        var components = URLComponents(
            url: baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false,
        )
        var queryItems = pathAndQuery.count == 2 ? queryItems(from: String(pathAndQuery[1])) : []
        queryItems.append(
            URLQueryItem(name: "X-Plex-Token", value: token),
        )
        components?.queryItems = queryItems
        return components?.url
    }

    private static func queryItems(from query: String) -> [URLQueryItem] {
        var components = URLComponents()
        components.percentEncodedQuery = query
        return components.queryItems ?? []
    }
}
