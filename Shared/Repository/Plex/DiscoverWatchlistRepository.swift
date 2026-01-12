import Foundation

final class DiscoverWatchlistRepository {
    private let network: PlexCloudNetworkClient

    init(context: PlexAPIContext) throws {
        guard let authToken = context.authTokenCloud else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexCloudNetworkClient(
            authToken: authToken,
            clientIdentifier: context.clientIdentifier,
            useDiscoverBaseURL: true,
        )
    }

    func getUserState(discoverID: String) async throws -> PlexDiscoverUserStateResponse {
        try await network.request(path: "/library/metadata/\(discoverID)/userState")
    }

    func addToWatchlist(ratingKey: String) async throws {
        try await network.send(
            path: "/actions/addToWatchlist",
            method: "PUT",
            queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)],
        )
    }

    func removeFromWatchlist(ratingKey: String) async throws {
        try await network.send(
            path: "/actions/removeFromWatchlist",
            method: "PUT",
            queryItems: [URLQueryItem(name: "ratingKey", value: ratingKey)],
        )
    }
}
