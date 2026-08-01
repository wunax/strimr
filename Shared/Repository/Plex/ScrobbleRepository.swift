import Foundation

final class ScrobbleRepository {
    private let network: PlexServerNetworkClient
    private let pluginIdentifier = "com.plexapp.plugins.library"

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(context: context)
    }

    func markWatched(key: String) async throws {
        try await network.send(
            path: "/:/scrobble",
            queryItems: queryItems(for: key),
        )
    }

    func markUnwatched(key: String) async throws {
        try await network.send(
            path: "/:/unscrobble",
            queryItems: queryItems(for: key),
        )
    }

    private func queryItems(for key: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "identifier", value: pluginIdentifier),
            URLQueryItem(name: "key", value: key),
        ]
    }
}
