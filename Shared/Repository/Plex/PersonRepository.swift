import Foundation

final class PersonRepository {
    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) throws {
        guard context.baseURLServer != nil else {
            throw PlexAPIError.missingConnection
        }

        guard context.authTokenServer != nil else {
            throw PlexAPIError.missingAuthToken
        }

        network = PlexServerNetworkClient(context: context)
    }

    func getPerson(id: String) async throws -> PlexPersonMediaContainer {
        try await network.request(path: "/library/people/\(id)")
    }

    func getMedia(id: String) async throws -> PlexItemMediaContainer {
        try await network.request(path: "/library/people/\(id)/media")
    }
}
