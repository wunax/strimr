import Foundation

struct ExternalPlaybackLauncher {
    let context: PlexAPIContext
    let callbackScheme: String = "strimr"

    func infuseURL(for ratingKey: String) async throws -> URL {
        let playbackURL = try await resolvePlaybackURL(for: ratingKey)
        guard let infuseURL = InfuseURLBuilder.make(playbackURL: playbackURL, callbackScheme: callbackScheme) else {
            throw PlexAPIError.invalidURL
        }

        return infuseURL
    }

    private func resolvePlaybackURL(for ratingKey: String) async throws -> URL {
        let metadataRepository = try MetadataRepository(context: context)
        let params = MetadataRepository.PlexMetadataParams(checkFiles: true)
        let response = try await metadataRepository.getMetadata(ratingKey: ratingKey, params: params)

        guard let partPath = response.mediaContainer.metadata?.first?.media?.first?.parts.first?.key else {
            throw PlexAPIError.invalidURL
        }

        let mediaRepository = try MediaRepository(context: context)
        guard let playbackURL = mediaRepository.mediaURL(path: partPath) else {
            throw PlexAPIError.invalidURL
        }

        return playbackURL
    }
}

private enum InfuseURLBuilder {
    static func make(playbackURL: URL, callbackScheme: String) -> URL? {
        let callbackSuccess = "\(callbackScheme)://x-callback-url/playbackDidFinish"
        let callbackError = "\(callbackScheme)://x-callback-url/playbackDidFail"

        guard
            let encodedPlayback = percentEncodeQueryValue(playbackURL.absoluteString)
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "infuse"
        components.host = "x-callback-url"
        components.path = "/play"
        components.percentEncodedQueryItems = [
            URLQueryItem(name: "x-success", value: callbackSuccess),
            URLQueryItem(name: "x-error", value: callbackError),
            URLQueryItem(name: "url", value: encodedPlayback),
        ]
        return components.url
    }

    private static func percentEncodeQueryValue(_ value: String) -> String? {
        let reserved = CharacterSet(charactersIn: ":/&=?+")
        return value.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed.subtracting(reserved))
    }
}
