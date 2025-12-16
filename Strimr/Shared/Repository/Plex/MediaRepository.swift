import Foundation

final class MediaRepository {
    private let baseURL: URL
    private let authToken: String

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenCloud else {
            throw PlexAPIError.missingAuthToken
        }

        self.baseURL = baseURLServer
        self.authToken = authToken
    }

    func mediaURL(path: String) -> URL? {
        var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false)
        let normalizedPath = path.hasPrefix("/") ? path : "/\(path)"
        components?.path = normalizedPath
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken)
        ]
        return components?.url
    }
}
