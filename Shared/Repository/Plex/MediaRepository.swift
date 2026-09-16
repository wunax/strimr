import Foundation

final class MediaRepository {
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        _ = try context.serverAccessSnapshot()
        self.context = context
    }

    func mediaURL(path: String) -> URL? {
        guard let snapshot = try? context?.serverAccessSnapshot() else { return nil }
        let pathAndQuery = path.split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false)
        let pathOnly = String(pathAndQuery[0])
        let normalizedPath = pathOnly.hasPrefix("/") ? pathOnly : "/\(pathOnly)"
        var components = URLComponents(
            url: snapshot.baseURL.appendingPathComponent(normalizedPath),
            resolvingAgainstBaseURL: false,
        )
        var queryItems = pathAndQuery.count == 2 ? queryItems(from: String(pathAndQuery[1])) : []
        queryItems.append(
            URLQueryItem(name: "X-Plex-Token", value: snapshot.authToken),
        )
        components?.queryItems = queryItems
        return components?.url
    }

    private func queryItems(from query: String) -> [URLQueryItem] {
        var components = URLComponents()
        components.percentEncodedQuery = query
        return components.queryItems ?? []
    }
}
