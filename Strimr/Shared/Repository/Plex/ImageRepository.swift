import Foundation

final class ImageRepository {
    private weak var context: PlexAPIContext?
    private let baseURL: URL
    private let authToken: String
    
    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }
        
        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }
        
        self.context = context
        self.baseURL = baseURLServer
        self.authToken = authToken
    }
    
    func transcodeImageURL(
        path: String,
        width: Int = 240,
        height: Int = 360,
        minSize: Int = 1,
        upscale: Int = 1
    ) -> URL? {
        var components = URLComponents(url: baseURL.appendingPathComponent("photo/:/transcode"), resolvingAgainstBaseURL: false)
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: authToken),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: String(minSize)),
            URLQueryItem(name: "upscale", value: String(upscale)),
        ]
        return components?.url
    }
}
