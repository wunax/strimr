import Foundation

final class PlaybackRepository {
    private let network: PlexServerNetworkClient
    private weak var context: PlexAPIContext?

    enum PlaybackState: String {
        case playing
        case buffering
        case paused
        case stopped
    }

    init(context: PlexAPIContext) throws {
        guard let baseURLServer = context.baseURLServer else {
            throw PlexAPIError.missingConnection
        }

        guard let authToken = context.authTokenServer else {
            throw PlexAPIError.missingAuthToken
        }

        self.context = context
        network = PlexServerNetworkClient(
            authToken: authToken,
            baseURL: baseURLServer,
            clientIdentifier: context.clientIdentifier,
        )
    }

    func setPreferredStreams(
        partId: Int,
        audioStreamId: Int? = nil,
        subtitleStreamId: Int? = nil,
        applyToAllParts: Bool = true,
    ) async throws {
        var queryItems: [URLQueryItem] = []

        if let audioStreamId {
            queryItems.append(URLQueryItem(name: "audioStreamID", value: String(audioStreamId)))
        }

        if let subtitleStreamId {
            queryItems.append(URLQueryItem(name: "subtitleStreamID", value: String(subtitleStreamId)))
        }

        queryItems.append(URLQueryItem(name: "allParts", value: applyToAllParts ? "1" : "0"))

        try await network.send(
            path: "/library/parts/\(partId)",
            queryItems: queryItems,
            method: "PUT",
        )
    }

    func updateTimeline(
        ratingKey: String,
        state: PlaybackState,
        time: Int,
        duration: Int,
        sessionIdentifier: String,
        playQueueItemID: Int? = nil,
    ) async throws -> PlexTimelineResponse {
        var queryItems = [
            URLQueryItem(name: "ratingKey", value: ratingKey),
            URLQueryItem(name: "state", value: state.rawValue),
            URLQueryItem(name: "time", value: String(time)),
            URLQueryItem(name: "duration", value: String(duration)),
        ]
        if let playQueueItemID {
            queryItems.append(URLQueryItem(name: "playQueueItemID", value: String(playQueueItemID)))
        }

        return try await network.request(
            path: "/:/timeline",
            queryItems: queryItems,
            headers: [
                "X-Plex-Session-Identifier": sessionIdentifier,
            ],
        )
    }
}
