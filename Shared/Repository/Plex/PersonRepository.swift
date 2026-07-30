import Foundation

final class PersonRepository {
    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(authToken: authToken, baseURL: baseURLServer)
    }

    func getPerson(id: Int) async throws -> PlexPersonMediaContainer {
        try await network.request(path: "/library/people/\(id)")
    }

    func getMedia(id: Int) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/people/\(id)/media")
    }
}
