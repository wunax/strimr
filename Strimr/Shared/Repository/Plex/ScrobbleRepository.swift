import Foundation

final class ScrobbleRepository {
    private let network: PlexServerNetworkClient
    private let pluginIdentifier = "com.plexapp.plugins.library"

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(
            authToken: authToken,
            baseURL: baseURLServer,
        )
    }

    func markWatched(key: String) async throws {
        try await network.send(
            path: "/:/scrobble",
            queryItems: queryItems(for: key)
        )
    }

    func markUnwatched(key: String) async throws {
        try await network.send(
            path: "/:/unscrobble",
            queryItems: queryItems(for: key)
        )
    }

    private func queryItems(for key: String) -> [URLQueryItem] {
        [
            URLQueryItem(name: "identifier", value: pluginIdentifier),
            URLQueryItem(name: "key", value: key),
        ]
    }
}
