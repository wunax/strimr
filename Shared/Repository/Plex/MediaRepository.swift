import Foundation

final class MediaRepository {
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        _ = try context.serverAccessSnapshot()
        self.context = context
    }

    func mediaURL(path: String) -> URL? {
        guard let snapshot = try? context?.serverAccessSnapshot() else { return nil }
        var components = URLComponents(url: snapshot.baseURL, resolvingAgainstBaseURL: false)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components?.path = normalizedPath
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: snapshot.authToken),
        ]
        return components?.url
    }
}
