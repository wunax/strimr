import Foundation

final class SeerrMediaRepository {
    private let client: SeerrNetworkClient

    init(baseURL: URL, session: URLSession = .shared) {
        client = SeerrNetworkClient(baseURL: baseURL, session: session)
    }

    func getMovie(id: Int) async throws -> SeerrMedia {
        try await client.request(path: "movie/\(id)")
    }

    func getTV(id: Int) async throws -> SeerrMedia {
        try await client.request(path: "tv/\(id)")
    }

    func getTVSeason(id: Int, seasonNumber: Int) async throws -> SeerrSeason {
        try await client.request(path: "tv/\(id)/season/\(seasonNumber)")
    }

    func getMovieRecommendations(id: Int, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        try await pagedRequest(path: "movie/\(id)/recommendations", page: page)
    }

    func getMovieSimilar(id: Int, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        try await pagedRequest(path: "movie/\(id)/similar", page: page)
    }

    func getTVRecommendations(id: Int, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        try await pagedRequest(path: "tv/\(id)/recommendations", page: page)
    }

    func getTVSimilar(id: Int, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        try await pagedRequest(path: "tv/\(id)/similar", page: page)
    }

    private func pagedRequest(path: String, page: Int) async throws -> SeerrPaginatedResponse<SeerrMedia> {
        let queryItems = [URLQueryItem(name: "page", value: String(page))]
        return try await client.request(path: path, queryItems: queryItems)
    }
}
