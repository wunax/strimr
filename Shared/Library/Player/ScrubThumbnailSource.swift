import Foundation

nonisolated enum ScrubThumbnailSource: @unchecked Sendable {
    case plex(PlexBIFSource)
    case jellyfin(JellyfinTrickplaySource)
}

protocol ScrubThumbnailProviding: Actor {
    func prepare() async
    func availability() async -> PlexBIFAvailability
    func thumbnail(at seconds: Double) async -> PlexBIFThumbnail?
    func cancel() async
}

extension PlexBIFThumbnailProvider: ScrubThumbnailProviding {}

nonisolated struct JellyfinTrickplaySource: Sendable {
    let directoryURL: URL
    let headers: [String: String]
    let cacheKey: String
    let mediaSourceID: String
    let width: Int
    let height: Int
    let tileColumns: Int
    let tileRows: Int
    let thumbnailCount: Int
    let intervalMilliseconds: Int

    func sheetURL(index: Int) -> URL? {
        let url = directoryURL.appendingPathComponent("\(index).jpg")
        guard var components = URLComponents(url: url, resolvingAgainstBaseURL: false) else { return nil }
        components.queryItems = [URLQueryItem(name: "MediaSourceId", value: mediaSourceID)]
        return components.url
    }
}
