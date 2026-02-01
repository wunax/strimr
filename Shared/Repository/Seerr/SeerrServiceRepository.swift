import Foundation

final class SeerrServiceRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getSonarrServers() async throws -> [SeerrSonarrServer] {
        try await client.request(path: "service/sonarr")
    }

    func getRadarrServers() async throws -> [SeerrRadarrServer] {
        try await client.request(path: "service/radarr")
    }

    func getSonarrService(id: Int) async throws -> SeerrSonarrServiceDetail {
        try await client.request(path: "service/sonarr/\(id)")
    }

    func getRadarrService(id: Int) async throws -> SeerrRadarrServiceDetail {
        try await client.request(path: "service/radarr/\(id)")
    }
}
