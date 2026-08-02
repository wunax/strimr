import Foundation

final class SubtitleRepository {
    private let network: PlexServerNetworkClient

    private static let attachmentPollDelays: [Duration] = [
        .zero,
        .milliseconds(250),
        .milliseconds(500),
        .seconds(1),
        .seconds(2),
        .seconds(4),
    ]

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
        /*
         Plex acknowledges the subtitle attachment before the server has necessarily added and
         selected the new stream in its metadata. Callers refresh their track selectors as soon as
         this method returns, so returning after the PUT alone can leave the interface showing the
         previous selection. Snapshot the current streams and wait for the new selection to become
         visible, keeping this eventual-consistency handling shared across every player and media view.
         */
        let previousSelection = try await subtitleSelectionState(ratingKey: ratingKey)
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

        try await waitForAttachedSubtitle(
            ratingKey: ratingKey,
            result: result,
            previousSelection: previousSelection,
        )
    }

    private func waitForAttachedSubtitle(
        ratingKey: String,
        result: PlexSubtitleSearchResult,
        previousSelection: SubtitleSelectionState,
    ) async throws {
        for delay in Self.attachmentPollDelays {
            if delay > .zero {
                try await Task.sleep(for: delay)
            }

            let state = try await subtitleSelectionState(ratingKey: ratingKey)
            let attachedStreamIsSelected = state.streams.contains { stream in
                guard stream.selected == true,
                      stream.key != nil,
                      stream.codec.caseInsensitiveCompare(result.codec) == .orderedSame,
                      let id = stream.id
                else { return false }

                return !previousSelection.streamIDs.contains(id)
                    || !previousSelection.selectedStreamIDs.contains(id)
            }
            if attachedStreamIsSelected {
                return
            }
        }

        throw PlexSubtitleAttachmentTimeoutError()
    }

    private func subtitleSelectionState(ratingKey: String) async throws -> SubtitleSelectionState {
        let response: PlexItemMediaContainer = try await network.request(
            path: "/library/metadata/\(ratingKey)",
            queryItems: [URLQueryItem(name: "checkFiles", value: "1")],
        )
        let streams = response.mediaContainer.metadata?
            .first?
            .media?
            .first?
            .parts
            .first?
            .stream?
            .filter { $0.streamType == .subtitle } ?? []

        return SubtitleSelectionState(
            streams: streams,
            streamIDs: Set(streams.compactMap(\.id)),
            selectedStreamIDs: Set(streams.filter { $0.selected == true }.compactMap(\.id)),
        )
    }
}

private struct SubtitleSelectionState {
    let streams: [PlexPartStream]
    let streamIDs: Set<Int>
    let selectedStreamIDs: Set<Int>
}

private struct PlexSubtitleAttachmentTimeoutError: LocalizedError {
    var errorDescription: String? {
        String(localized: "subtitles.search.activation.error")
    }
}
