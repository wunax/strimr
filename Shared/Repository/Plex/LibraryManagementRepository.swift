import Foundation

final class LibraryManagementRepository {
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

    func getServerRoot() async throws -> PlexServerRootResponse {
        try await network.request(path: "/")
    }

    func refreshMetadata(ratingKey: String) async throws {
        try await network.send(
            path: "/library/metadata/\(ratingKey)/refresh",
            queryItems: [URLQueryItem(name: "force", value: "1")],
            method: "PUT",
        )
    }

    func analyze(ratingKey: String) async throws {
        try await network.send(path: "/library/metadata/\(ratingKey)/analyze", method: "PUT")
    }
}
