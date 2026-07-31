import Foundation

nonisolated struct PlexBIFValidators: Codable, Equatable, Sendable {
    var etag: String?
    var lastModified: String?

    nonisolated var hasValidator: Bool {
        etag != nil || lastModified != nil
    }
}

nonisolated enum PlexBIFRepositoryResult: @unchecked Sendable {
    case downloaded(fileURL: URL, validators: PlexBIFValidators)
    case notModified(validators: PlexBIFValidators)
    case unavailable
}

final class PlexBIFRepository: @unchecked Sendable {
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

    func fetch(
        partID: Int,
        intervalMilliseconds: Int,
        validators: PlexBIFValidators? = nil,
    ) async throws -> PlexBIFRepositoryResult {
        var headers = ["Accept": "application/octet-stream"]
        if let etag = validators?.etag {
            headers["If-None-Match"] = etag
        }
        if let lastModified = validators?.lastModified {
            headers["If-Modified-Since"] = lastModified
        }

        let download = try await network.download(
            path: "/library/parts/\(partID)/indexes/sd",
            queryItems: [
                URLQueryItem(
                    name: "interval",
                    value: String(intervalMilliseconds),
                ),
            ],
            headers: headers,
            acceptedStatusCodes: Set(200 ..< 300).union([304, 404, 410]),
        )
        let responseValidators = PlexBIFValidators(
            etag: download.response.value(forHTTPHeaderField: "ETag") ?? validators?.etag,
            lastModified: download.response.value(forHTTPHeaderField: "Last-Modified")
                ?? validators?.lastModified,
        )

        switch download.response.statusCode {
        case 200 ..< 300:
            return .downloaded(
                fileURL: download.temporaryFileURL,
                validators: responseValidators,
            )
        case 304:
            try? FileManager.default.removeItem(at: download.temporaryFileURL)
            return .notModified(validators: responseValidators)
        case 404, 410:
            try? FileManager.default.removeItem(at: download.temporaryFileURL)
            return .unavailable
        default:
            try? FileManager.default.removeItem(at: download.temporaryFileURL)
            throw PlexAPIError.requestFailed(statusCode: download.response.statusCode)
        }
    }
}

nonisolated struct PlexBIFSource: @unchecked Sendable {
    let partID: Int
    let serverIdentity: String
    let repository: PlexBIFRepository

    @MainActor
    init?(partID: Int?, context: PlexAPIContext) {
        guard let partID,
              let repository = try? PlexBIFRepository(context: context)
        else {
            return nil
        }
        let identity = context.serverIdentifier
            ?? context.baseURLServer?.absoluteString
            ?? "unknown-server"

        self.partID = partID
        serverIdentity = identity
        self.repository = repository
    }
}
