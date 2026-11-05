import Foundation

nonisolated enum SimklAPI {
    static let clientID = "8788ef20dbc533e6950586723a90892be6c07c54864d31a443de7d11421547ab"
    static let baseURL = URL(string: "https://api.simkl.com")!
    static let scope = "media:read media:write"
    static let writeScope = "media:write"

    private static let dailyQuotaFallback: TimeInterval = 60 * 60
    private static let unknownLimitFallback: TimeInterval = 60
    /// The per-second limit clears almost at once, and any `Retry-After` on it carries the daily reset.
    private static let burstHold: TimeInterval = 2

    static func url(path: String) -> URL {
        baseURL.appending(path: path).appending(queryItems: [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "app-name", value: "strimr"),
            URLQueryItem(name: "app-version", value: TrackerAppInfo.version),
        ])
    }

    static func headers(token: String? = nil) -> [String: String] {
        var headers = ["User-Agent": TrackerAppInfo.userAgent, "Accept": "application/json"]
        headers["Authorization"] = token.map { "Bearer \($0)" }
        return headers
    }

    /// Simkl's docs ask for every identifier available, title and year included, to improve matching.
    static func media(_ item: TrackerItem) -> [String: Any]? {
        var ids: [String: Any] = [:]
        ids["imdb"] = item.ids.imdb
        ids["tmdb"] = item.ids.tmdb
        ids["tvdb"] = item.ids.tvdb
        guard !ids.isEmpty else { return nil }
        var media: [String: Any] = ["ids": ids]
        media["title"] = item.title
        media["year"] = item.year
        return media
    }

    static func error(for response: TrackerHTTPResponse) -> TrackerAPIError {
        let body = response.bodyText
        switch response.statusCode {
        case 400 where body.contains("RATE_LIMIT"): return .writeLocked
        case 401: return .unauthorized
        case 404: return .notFound
        case 409: return .conflict
        case 412: return .throttled
        case 429:
            if body.contains("user_limit_exceeded") || body.contains("app_limit_exceeded") {
                return .rateLimited(retryAfter: response.retryAfter ?? dailyQuotaFallback)
            }
            if body.contains("rate_limit") {
                return .rateLimited(retryAfter: burstHold)
            }
            return .rateLimited(retryAfter: response.retryAfter ?? unknownLimitFallback)
        case 500 ... 599: return .server(status: response.statusCode)
        default: return .unexpected(status: response.statusCode)
        }
    }

    static func pollResult(for response: TrackerHTTPResponse, now: Date) throws -> TrackerDevicePollResult {
        if response.statusCode == 200 {
            let tokens = try response.decode(TrackerTokenResponse.self)
            // An unknown or missing scope is silently downgraded to read-only, which would fail every write later.
            guard tokens.scope?.split(separator: " ").contains(Substring(writeScope)) == true else {
                return .missingWriteScope
            }
            guard let session = tokens.session(now: now) else { throw TrackerAPIError.invalidResponse }
            return .authorized(session)
        }
        struct Failure: Decodable {
            let error: String?
        }
        switch (try? JSONDecoder().decode(Failure.self, from: response.data))?.error {
        case "slow_down": return .slowDown
        case "expired_token": return .expired
        case "access_denied": return .denied
        case "invalid_client": return .invalidClient
        default: return .pending
        }
    }
}

@MainActor
final class SimklDeviceFlow: TrackerDeviceFlow {
    private let http: TrackerHTTP
    private let now: () -> Date

    init(http: TrackerHTTP = TrackerHTTP(), now: @escaping () -> Date = Date.init) {
        self.http = http
        self.now = now
    }

    private struct CodeResponse: Decodable {
        let device_code: String
        let user_code: String
        let verification_uri: URL
        let verification_uri_complete: URL?
        let expires_in: TimeInterval?
        let interval: TimeInterval?
    }

    func requestCode() async throws -> TrackerDeviceCode {
        let response = try await http.send(.trackerForm(
            url: SimklAPI.baseURL.appending(path: "oauth2/device"),
            headers: SimklAPI.headers(),
            fields: ["client_id": SimklAPI.clientID, "scope": SimklAPI.scope],
        ))
        guard response.isSuccess else { throw SimklAPI.error(for: response) }
        let code = try response.decode(CodeResponse.self)
        return TrackerDeviceCode(
            deviceCode: code.device_code,
            userCode: code.user_code,
            verificationURL: code.verification_uri,
            scanURL: code.verification_uri_complete ?? code.verification_uri,
            expiresIn: code.expires_in ?? 900,
            interval: code.interval ?? 5,
        )
    }

    func poll(_ code: TrackerDeviceCode) async throws -> TrackerDevicePollResult {
        let response = try await http.send(.trackerForm(
            url: SimklAPI.baseURL.appending(path: "oauth2/token"),
            headers: SimklAPI.headers(),
            fields: [
                "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
                "client_id": SimklAPI.clientID,
                "device_code": code.deviceCode,
            ],
        ))
        return try SimklAPI.pollResult(for: response, now: now())
    }
}

@MainActor
final class SimklClient: TrackerClient {
    let service = TrackerService.simkl
    let policy = TrackerPlaybackPolicy(resendThrottle: 20, watchedProgress: 80)

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
            mapError: SimklAPI.error(for:),
        )
    }

    private static func refresh(
        _ session: TrackerSession,
        http: TrackerHTTP,
        now: () -> Date,
    ) async throws -> TrackerSession {
        let response = try await http.send(.trackerForm(
            url: SimklAPI.baseURL.appending(path: "oauth2/token"),
            headers: SimklAPI.headers(),
            fields: [
                "grant_type": "refresh_token",
                "client_id": SimklAPI.clientID,
                "refresh_token": session.refreshToken,
            ],
        ))
        guard response.isSuccess else {
            if response.statusCode == 400 || response.statusCode == 401 {
                throw TrackerAPIError.sessionExpired
            }
            throw SimklAPI.error(for: response)
        }
        let tokens = try response.decode(TrackerTokenResponse.self)
        guard let renewed = tokens.session(now: now(), keepingRefreshToken: session.refreshToken) else {
            throw TrackerAPIError.invalidResponse
        }
        return renewed
    }

    func currentUser() async throws -> TrackerUser {
        struct Settings: Decodable {
            struct User: Decodable {
                let name: String?
            }

            let user: User?
        }
        let response = try await transport.read { token in
            .trackerJSON(
                url: SimklAPI.url(path: "users/settings"),
                method: "GET",
                headers: SimklAPI.headers(token: token),
                body: nil,
            )
        }
        return try TrackerUser(username: response.decode(Settings.self).user?.name)
    }

    func report(_ event: TrackerPlaybackEvent, item: TrackerItem, progress: Double) async throws {
        guard let body = TrackerRequestBody.scrobble(item: item, progress: progress, media: SimklAPI.media) else {
            return
        }
        try await post(path: "scrobble/\(event.rawValue)", body: body)
    }

    func addToHistory(_ entries: [TrackerHistoryEntry]) async throws {
        guard let body = TrackerRequestBody.history(entries, media: SimklAPI.media) else { return }
        try await post(path: "sync/history", body: body)
    }

    func removeFromHistory(_ items: [TrackerItem]) async throws {
        let entries = items.map { TrackerHistoryEntry(item: $0, watchedAt: nil) }
        guard let body = TrackerRequestBody.history(entries, media: SimklAPI.media) else { return }
        try await post(path: "sync/history/remove", body: body)
    }

    func revoke() async {
        _ = try? await http.send(.trackerForm(
            url: SimklAPI.baseURL.appending(path: "oauth2/revoke"),
            headers: SimklAPI.headers(),
            fields: ["client_id": SimklAPI.clientID, "token": transport.tokens.session.refreshToken],
        ))
    }

    private func post(path: String, body: [String: Any]) async throws {
        let payload = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        try await transport.write { token in
            var request = URLRequest.trackerJSON(
                url: SimklAPI.url(path: path),
                headers: SimklAPI.headers(token: token),
                body: nil,
            )
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = payload
            return request
        }
    }
}
