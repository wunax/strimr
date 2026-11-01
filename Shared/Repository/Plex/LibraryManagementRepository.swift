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

    /// `force` also refreshes the metadata of every item, not only of new files.
    func scanSection(sectionID: String, force: Bool) async throws {
        try await network.send(
            path: "/library/sections/\(sectionID)/refresh",
            queryItems: force ? [URLQueryItem(name: "force", value: "1")] : nil,
            method: "GET",
        )
    }

    func analyzeSection(sectionID: String) async throws {
        try await network.send(path: "/library/sections/\(sectionID)/analyze", method: "PUT")
    }

    func emptySectionTrash(sectionID: String) async throws {
        try await network.send(path: "/library/sections/\(sectionID)/emptyTrash", method: "PUT")
    }
}
