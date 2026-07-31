import Foundation

final class ImageRepository {
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) throws {
        _ = try context.serverAccessSnapshot()
        self.context = context
    }

    func transcodeImageURL(
        path: String,
        width: Int = 240,
        height: Int = 360,
        minSize: Int = 1,
        upscale: Int = 1,
    ) -> URL? {
        guard let snapshot = try? context?.serverAccessSnapshot() else { return nil }
        var components = URLComponents(
            url: snapshot.baseURL.appendingPathComponent("photo/:/transcode"),
            resolvingAgainstBaseURL: false,
        )
        components?.queryItems = [
            URLQueryItem(name: "X-Plex-Token", value: snapshot.authToken),
            URLQueryItem(name: "url", value: path),
            URLQueryItem(name: "width", value: String(width)),
            URLQueryItem(name: "height", value: String(height)),
            URLQueryItem(name: "minSize", value: String(minSize)),
            URLQueryItem(name: "upscale", value: String(upscale)),
        ]
        return components?.url
    }
}
