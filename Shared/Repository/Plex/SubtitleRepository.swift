import Foundation

final class SubtitleRepository {
    private let network: PlexServerNetworkClient

    init(context: PlexAPIContext) {
        network = PlexServerNetworkClient(context: context)
    }

    func search(
        ratingKey: String,
        language: String,
        hearingImpaired: Bool,
        forced: Bool,
        title: String?,
    ) async throws -> [PlexSubtitleSearchResult] {
        var queryItems = [
            URLQueryItem(name: "language", value: language),
            URLQueryItem(name: "hearingImpaired", value: hearingImpaired ? "1" : "0"),
            URLQueryItem(name: "forced", value: forced ? "1" : "0"),
        ]
        if let title = title?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty {
            queryItems.append(URLQueryItem(name: "title", value: title))
        }

        let response: PlexSubtitleSearchResponse = try await network.request(
            path: "/library/metadata/\(ratingKey)/subtitles",
            queryItems: queryItems,
        )
        return response.mediaContainer.streams ?? []
    }

    func attach(
        ratingKey: String,
        result: PlexSubtitleSearchResult,
        searchedLanguage: String,
        searchedHearingImpaired: Bool,
        searchedForced: Bool,
    ) async throws {
        let language = result.languageTag ?? result.languageCode ?? searchedLanguage
        var queryItems = [
            URLQueryItem(name: "key", value: result.key),
            URLQueryItem(name: "codec", value: result.codec),
            URLQueryItem(name: "language", value: language),
            URLQueryItem(
                name: "hearingImpaired",
                value: (result.hearingImpaired ?? searchedHearingImpaired) ? "1" : "0",
            ),
            URLQueryItem(name: "forced", value: (result.forced ?? searchedForced) ? "1" : "0"),
        ]
        if let providerTitle = result.providerTitle, !providerTitle.isEmpty {
            queryItems.append(URLQueryItem(name: "providerTitle", value: providerTitle))
        }

        try await network.send(
            path: "/library/metadata/\(ratingKey)/subtitles",
            queryItems: queryItems,
            method: "PUT",
        )
    }
}
