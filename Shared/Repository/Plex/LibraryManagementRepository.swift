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

    /// A series or a season deletes all its episodes.
    func deleteMetadata(ratingKey: String) async throws {
        try await network.send(path: "/library/metadata/\(ratingKey)", method: "DELETE")
    }

    /// `element` is `poster`, `art` or `clearLogo`; its list lives at the plural path.
    func artwork(ratingKey: String, element: String) async throws -> PlexArtworkResponse {
        try await network.request(path: "/library/metadata/\(ratingKey)/\(element)s")
    }

    func selectArtwork(ratingKey: String, element: String, url: String) async throws {
        try await network.send(
            path: "/library/metadata/\(ratingKey)/\(element)",
            queryItems: [URLQueryItem(name: "url", value: url)],
            method: "PUT",
            encodesPlusSign: true,
        )
    }

    /// Plex takes the raw image bytes as the body.
    func uploadArtwork(ratingKey: String, element: String, data: Data, contentType: String) async throws {
        try await network.send(
            path: "/library/metadata/\(ratingKey)/\(element)s",
            method: "POST",
            headers: ["Content-Type": contentType],
            body: data,
        )
    }
}
