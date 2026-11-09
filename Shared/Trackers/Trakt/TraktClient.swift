import Foundation

nonisolated enum TraktAPI {
    static let clientID = "A-yBlYoCBeTGUq8U467O2BkqtgHdV31i9vTLo672F1Y"
    static let baseURL = URL(string: "https://api.trakt.tv")!
    /// The hosted activation page Trakt recommends for a QR code.
    static let activationURL = URL(string: "https://auth.trakt.tv/activate")!

    static func headers(token: String? = nil) -> [String: String] {
        var headers = [
            "User-Agent": TrackerAppInfo.userAgent,
            "trakt-api-version": "2",
            "trakt-api-key": clientID,
        ]
        headers["Authorization"] = token.map { "Bearer \($0)" }
        return headers
    }

    /// Trakt wants numeric tmdb and tvdb ids, and movies have no tvdb id.
    static func media(_ item: TrackerItem) -> [String: Any]? {
        var ids: [String: Any] = [:]
        ids["imdb"] = item.ids.imdb
        ids["tmdb"] = item.ids.tmdb.flatMap(Int.init)
        if item.kind == .episode {
            ids["tvdb"] = item.ids.tvdb.flatMap(Int.init)
        }
        return ids.isEmpty ? nil : ["ids": ids]
    }

    static func error(for response: TrackerHTTPResponse) -> TrackerAPIError {
        switch response.statusCode {
        case 401: .unauthorized
        case 404: .notFound
        case 409: .conflict
        case 420, 426: .accountLimit
        case 423: .accountLocked
        case 429: .rateLimited(retryAfter: response.retryAfter)
        case 500 ... 599: .server(status: response.statusCode)
        default: .unexpected(status: response.statusCode)
        }
    }

    static func pollResult(for response: TrackerHTTPResponse, now: Date) throws -> TrackerDevicePollResult {
        switch response.statusCode {
        case 200:
            guard let session = try response.decode(TrackerTokenResponse.self).session(now: now) else {
                throw TrackerAPIError.invalidResponse
            }
            return .authorized(session)
        case 400: return .pending
        case 404, 410: return .expired
        // 409 means this code was already used, so polling again cannot yield a token.
        case 409, 418: return .denied
        case 429: return .slowDown
        default: return .pending
        }
    }
}

@MainActor
final class TraktDeviceFlow: TrackerDeviceFlow {
    private let http: TrackerHTTP
    private let now: () -> Date

    init(http: TrackerHTTP = TrackerHTTP(), now: @escaping () -> Date = Date.init) {
        self.http = http
        self.now = now
    }

    private struct CodeResponse: Decodable {
        let device_code: String
        let user_code: String
        let verification_url: URL
        let expires_in: TimeInterval
        let interval: TimeInterval
    }

    func requestCode() async throws -> TrackerDeviceCode {
        let response = try await http.send(.trackerJSON(
            url: TraktAPI.baseURL.appending(path: "oauth/device/code"),
            headers: TraktAPI.headers(),
            body: ["client_id": TraktAPI.clientID],
        ))
        guard response.isSuccess else { throw TraktAPI.error(for: response) }
        let code = try response.decode(CodeResponse.self)
        return TrackerDeviceCode(
            deviceCode: code.device_code,
            userCode: code.user_code,
            verificationURL: code.verification_url,
            scanURL: TraktAPI.activationURL,
            expiresIn: code.expires_in,
            interval: code.interval,
        )
    }

    func poll(_ code: TrackerDeviceCode) async throws -> TrackerDevicePollResult {
        let response = try await http.send(.trackerJSON(
            url: TraktAPI.baseURL.appending(path: "oauth/device/token"),
            headers: TraktAPI.headers(),
            body: ["code": code.deviceCode, "client_id": TraktAPI.clientID],
        ))
        return try TraktAPI.pollResult(for: response, now: now())
    }
}

@MainActor
final class TraktClient: TrackerClient {
    let service = TrackerService.trakt
    let policy = TrackerPlaybackPolicy(resendThrottle: 30, watchedProgress: 80)

    private let http: TrackerHTTP
    private let transport: TrackerTransport

    init(
        session: TrackerSession,
        http: TrackerHTTP = TrackerHTTP(),
        gate: TrackerWriteGate? = nil,
        now: @escaping () -> Date = Date.init,
        onUpdated: @escaping (TrackerSession) -> Void,
        onInvalidated: @escaping () -> Void,
    ) {
        self.http = http
        let tokens = TrackerTokenProvider(
            session: session,
            refresh: { try await Self.refresh($0, http: http, now: now) },
            onUpdated: onUpdated,
            onInvalidated: onInvalidated,
            now: now,
        )
        transport = TrackerTransport(
            tokens: tokens,
            http: http,
            gate: gate ?? TrackerWriteGate(),
            mapError: TraktAPI.error(for:),
        )
    }

    private static func refresh(
        _ session: TrackerSession,
        http: TrackerHTTP,
        now: () -> Date,
    ) async throws -> TrackerSession {
        let response = try await http.send(.trackerJSON(
            url: TraktAPI.baseURL.appending(path: "oauth/token"),
            headers: TraktAPI.headers(),
            body: [
                "refresh_token": session.refreshToken,
                "client_id": TraktAPI.clientID,
                "grant_type": "refresh_token",
            ],
        ))
        guard response.isSuccess else {
            if [400, 401].contains(response.statusCode) {
                throw TrackerAPIError.sessionExpired
            }
            throw TraktAPI.error(for: response)
        }
        guard let renewed = try response.decode(TrackerTokenResponse.self).session(now: now()) else {
            throw TrackerAPIError.invalidResponse
        }
        return renewed
    }

    func currentUser() async throws -> TrackerUser {
        struct Settings: Decodable {
            struct User: Decodable {
                let username: String?
            }

            let user: User?
        }
        let response = try await transport.read { token in
            .trackerJSON(
                url: TraktAPI.baseURL.appending(path: "users/settings"),
                method: "GET",
                headers: TraktAPI.headers(token: token),
                body: nil,
            )
        }
        return try TrackerUser(username: response.decode(Settings.self).user?.username)
    }

    func report(_ event: TrackerPlaybackEvent, item: TrackerItem, progress: Double) async throws {
        guard let body = TrackerRequestBody.scrobble(item: item, progress: progress, media: TraktAPI.media) else {
            return
        }
        try await post(path: "scrobble/\(event.rawValue)", body: body)
    }

    func addToHistory(_ entries: [TrackerHistoryEntry]) async throws {
        guard let body = TrackerRequestBody.history(entries, media: TraktAPI.media) else { return }
        try await post(path: "sync/history", body: body)
    }

    func removeFromHistory(_ items: [TrackerItem]) async throws {
        let entries = items.map { TrackerHistoryEntry(item: $0, watchedAt: nil) }
        guard let body = TrackerRequestBody.history(entries, media: TraktAPI.media) else { return }
        try await post(path: "sync/history/remove", body: body)
    }

    func revoke() async {
        _ = try? await http.send(.trackerJSON(
            url: TraktAPI.baseURL.appending(path: "oauth/revoke"),
            headers: TraktAPI.headers(),
            body: ["token": transport.tokens.session.accessToken, "client_id": TraktAPI.clientID],
        ))
    }

    private func post(path: String, body: [String: Any]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        try await transport.write { token in
            var request = URLRequest.trackerJSON(
                url: TraktAPI.baseURL.appending(path: path),
                headers: TraktAPI.headers(token: token),
                body: nil,
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }
    }
}
