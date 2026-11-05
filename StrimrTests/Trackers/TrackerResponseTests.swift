import Foundation
@testable import Strimr
import Testing

struct TrackerResponseTests {
    private func response(_ status: Int, _ body: String = "", retryAfter: TimeInterval? = nil) -> TrackerHTTPResponse {
        TrackerHTTPResponse(statusCode: status, data: Data(body.utf8), retryAfter: retryAfter)
    }

    private let now = Date(timeIntervalSince1970: 1000)

    @Test(arguments: [
        (404, TrackerAPIError.notFound),
        (409, .conflict),
        (420, .accountLimit),
        (426, .accountLimit),
        (423, .accountLocked),
        (503, .server(status: 503)),
        (422, .unexpected(status: 422)),
    ])
    func `trakt maps statuses`(status: Int, expected: TrackerAPIError) {
        #expect(TraktAPI.error(for: response(status)) == expected)
    }

    @Test func `trakt keeps the retry delay of a rate limit`() {
        #expect(TraktAPI.error(for: response(429, retryAfter: 12)) == .rateLimited(retryAfter: 12))
    }

    @Test func `simkl tells its write lock from a plain bad request`() {
        #expect(SimklAPI.error(for: response(400, #"{"error":"RATE_LIMIT"}"#)) == .writeLocked)
        #expect(SimklAPI.error(for: response(400, #"{"error":"empty_field"}"#)) == .unexpected(status: 400))
    }

    @Test func `simkl ignores the retry delay of a burst, which carries the daily reset`() {
        let body = #"{"error":"rate_limit"}"#
        #expect(SimklAPI.error(for: response(429, body, retryAfter: 40000)) == .rateLimited(retryAfter: 2))
    }

    @Test func `simkl waits for the daily quota to come back`() {
        let body = #"{"error":"user_limit_exceeded"}"#
        #expect(SimklAPI.error(for: response(429, body, retryAfter: 40000)) == .rateLimited(retryAfter: 40000))
        #expect(SimklAPI.error(for: response(429, body)) == .rateLimited(retryAfter: 3600))
    }

    @Test func `trakt device polling follows its status codes`() throws {
        #expect(try TraktAPI.pollResult(for: response(400), now: now) == .pending)
        #expect(try TraktAPI.pollResult(for: response(429), now: now) == .slowDown)
        #expect(try TraktAPI.pollResult(for: response(404), now: now) == .expired)
        #expect(try TraktAPI.pollResult(for: response(410), now: now) == .expired)
        #expect(try TraktAPI.pollResult(for: response(418), now: now) == .denied)
        #expect(try TraktAPI.pollResult(for: response(409), now: now) == .denied)
    }

    @Test func `a device token becomes a session expiring when announced`() throws {
        let body = #"{"access_token":"a","refresh_token":"r","expires_in":604800}"#

        let result = try TraktAPI.pollResult(for: response(200, body), now: now)

        #expect(result == .authorized(TrackerSession(
            accessToken: "a",
            refreshToken: "r",
            expiresAt: now.addingTimeInterval(604_800),
        )))
    }

    @Test func `simkl device polling follows its error names`() throws {
        func result(_ error: String) throws -> TrackerDevicePollResult {
            try SimklAPI.pollResult(for: response(400, #"{"error":"\#(error)"}"#), now: now)
        }
        #expect(try result("authorization_pending") == .pending)
        #expect(try result("slow_down") == .slowDown)
        #expect(try result("expired_token") == .expired)
        #expect(try result("invalid_client") == .invalidClient)
    }

    @Test func `simkl refuses a token that cannot write`() throws {
        let body = #"{"access_token":"a","refresh_token":"r","expires_in":604800,"scope":"media:read"}"#

        #expect(try SimklAPI.pollResult(for: response(200, body), now: now) == .missingWriteScope)
    }

    @Test func `simkl accepts a token with the write scope`() throws {
        let body = #"{"access_token":"a","refresh_token":"r","expires_in":604800,"scope":"media:read media:write"}"#

        guard case .authorized = try SimklAPI.pollResult(for: response(200, body), now: now) else {
            Issue.record("Expected a session")
            return
        }
    }

    @Test func `a refresh answer without a refresh token keeps the current one`() throws {
        let tokens = try JSONDecoder().decode(
            TrackerTokenResponse.self,
            from: Data(#"{"access_token":"a2"}"#.utf8),
        )

        #expect(tokens.session(now: now, keepingRefreshToken: "r1")?.refreshToken == "r1")
        #expect(tokens.session(now: now) == nil)
    }
}
