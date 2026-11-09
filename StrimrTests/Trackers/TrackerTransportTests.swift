import Foundation
@testable import Strimr
import Testing

@MainActor
struct TrackerTransportTests {
    private let now = Date(timeIntervalSince1970: 1000)

    private func session(expiresIn: TimeInterval = 7 * 24 * 3600) -> TrackerSession {
        TrackerSession(accessToken: "old", refreshToken: "r1", expiresAt: now.addingTimeInterval(expiresIn))
    }

    private func gate() -> TrackerWriteGate {
        TrackerWriteGate(spacing: .zero)
    }

    private final class Recorder {
        var updated: [TrackerSession] = []
        var invalidated = 0
    }

    private func trakt(_ stub: HTTPStub, session: TrackerSession, recorder: Recorder) -> TraktClient {
        let now = now
        return TraktClient(
            session: session,
            http: TrackerHTTP(session: stub.session),
            gate: gate(),
            now: { now },
            onUpdated: { recorder.updated.append($0) },
            onInvalidated: { recorder.invalidated += 1 },
        )
    }

    private nonisolated static let renewed = #"{"access_token":"new","refresh_token":"r2","expires_in":604800}"#

    @Test func `a 401 renews the token once and retries`() async throws {
        let stub = HTTPStub { request in
            if request.url?.path == "/oauth/token" {
                return .json(Self.renewed)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new" ? .json("{}") : .status(401)
        }
        let recorder = Recorder()
        let client = trakt(stub, session: session(), recorder: recorder)

        try await client.report(.start, item: TrackerFixtures.movie, progress: 5)

        #expect(stub.requests.map(\.url?.path) == ["/scrobble/start", "/oauth/token", "/scrobble/start"])
        #expect(recorder.updated.map(\.refreshToken) == ["r2"])
    }

    @Test func `concurrent rejections share one renewal, as a trakt refresh token works once`() async throws {
        let stub = HTTPStub { request in
            if request.url?.path == "/oauth/token" {
                return .json(Self.renewed)
            }
            return request.value(forHTTPHeaderField: "Authorization") == "Bearer new" ? .json("{}") : .status(401)
        }
        let client = trakt(stub, session: session(), recorder: Recorder())

        async let first: Void = client.report(.start, item: TrackerFixtures.movie, progress: 5)
        async let second: Void = client.addToHistory([TrackerHistoryEntry(item: TrackerFixtures.movie, watchedAt: nil)])
        _ = try await (first, second)

        #expect(stub.requests.count(where: { $0.url?.path == "/oauth/token" }) == 1)
    }

    @Test func `a refused renewal ends the session`() async {
        let stub = HTTPStub { request in
            request.url?.path == "/oauth/token"
                ? .json(#"{"error":"invalid_grant"}"#, statusCode: 400)
                : .status(401)
        }
        let recorder = Recorder()
        let client = trakt(stub, session: session(), recorder: recorder)

        await #expect(throws: TrackerAPIError.sessionExpired) {
            try await client.report(.start, item: TrackerFixtures.movie, progress: 5)
        }
        #expect(recorder.invalidated == 1)
    }

    @Test func `a server failure while renewing does not end the session`() async {
        let stub = HTTPStub { request in
            request.url?.path == "/oauth/token" ? .status(503) : .status(401)
        }
        let recorder = Recorder()
        let client = trakt(stub, session: session(), recorder: recorder)

        await #expect(throws: TrackerAPIError.server(status: 503)) {
            try await client.report(.start, item: TrackerFixtures.movie, progress: 5)
        }
        #expect(recorder.invalidated == 0)
    }

    @Test func `a token close to expiry is renewed before use`() async throws {
        let stub = HTTPStub { request in
            request.url?.path == "/oauth/token" ? .json(Self.renewed) : .json("{}")
        }
        let client = trakt(stub, session: session(expiresIn: 60), recorder: Recorder())

        try await client.report(.start, item: TrackerFixtures.movie, progress: 5)

        #expect(stub.requests.first?.url?.path == "/oauth/token")
        #expect(stub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer new")
    }

    @Test func `a token close to expiry stays usable when the renewal fails`() async throws {
        let stub = HTTPStub { request in
            request.url?.path == "/oauth/token" ? .status(503) : .json("{}")
        }
        let client = trakt(stub, session: session(expiresIn: 60), recorder: Recorder())

        try await client.report(.start, item: TrackerFixtures.movie, progress: 5)

        #expect(stub.requests.last?.value(forHTTPHeaderField: "Authorization") == "Bearer old")
    }

    @Test func `trakt never sends a client secret`() async throws {
        let stub = HTTPStub { _ in .json(Self.renewed) }
        let flow = TraktDeviceFlow(http: TrackerHTTP(session: stub.session))
        let code = TrackerDeviceCode(
            deviceCode: "device",
            userCode: "CODE",
            verificationURL: TraktAPI.activationURL,
            scanURL: TraktAPI.activationURL,
            expiresIn: 600,
            interval: 5,
        )

        _ = try await flow.poll(code)
        let client = trakt(stub, session: session(expiresIn: 60), recorder: Recorder())
        try await client.report(.start, item: TrackerFixtures.movie, progress: 5)

        for request in stub.requests where request.url?.path.contains("oauth") == true {
            #expect(request.jsonBody?["client_secret"] == nil)
        }
    }

    @Test func `simkl requests carry the app identity and a form encoded scope`() async throws {
        let stub = HTTPStub { _ in
            .json(#"{"device_code":"d","user_code":"U","verification_uri":"https://simkl.com/pin"}"#)
        }
        let flow = SimklDeviceFlow(http: TrackerHTTP(session: stub.session))

        let code = try await flow.requestCode()

        #expect(code.expiresIn == 900)
        #expect(code.interval == 5)
        #expect(stub.requests.first?.formBody["scope"] == "media:read media:write")

        let now = now
        let client = SimklClient(
            session: session(),
            http: TrackerHTTP(session: stub.session),
            gate: gate(),
            now: { now },
            onUpdated: { _ in },
            onInvalidated: {},
        )
        try await client.report(.stop, item: TrackerFixtures.movie, progress: 90)

        let url = try #require(stub.requests.last?.url)
        let query = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems)
        #expect(query.contains(URLQueryItem(name: "app-name", value: "strimr")))
        #expect(query.contains(URLQueryItem(name: "client_id", value: SimklAPI.clientID)))
    }

    @Test func `writes run one at a time, in order`() async throws {
        let order = OrderRecorder()
        let gate = TrackerWriteGate(spacing: .zero)

        async let first: Void = gate.run {
            await order.append("first start")
            await Task.yield()
            await order.append("first end")
        }
        async let second: Void = gate.run {
            await order.append("second")
        }
        _ = try await (first, second)

        #expect(await order.values.firstIndex(of: "first end") == order.values.firstIndex(of: "first start")
            .map { $0 + 1 })
    }

    @Test func `writes wait for the gap after the previous one`() async throws {
        let sleeps = OrderRecorder()
        let gate = TrackerWriteGate(spacing: .seconds(1)) { duration in
            await sleeps.append("\(duration)")
        }

        try await gate.run {}
        try await gate.run {}

        #expect(await sleeps.values.first == "\(Duration.seconds(1))")
    }

    private struct PollFlow: TrackerDeviceFlow {
        let results: PollResults

        func requestCode() async throws -> TrackerDeviceCode {
            throw TrackerAPIError.invalidResponse
        }

        func poll(_: TrackerDeviceCode) async throws -> TrackerDevicePollResult {
            try results.next()
        }
    }

    private final class PollResults {
        var values: [Result<TrackerDevicePollResult, Error>]

        init(_ values: [Result<TrackerDevicePollResult, Error>]) {
            self.values = values
        }

        func next() throws -> TrackerDevicePollResult {
            guard !values.isEmpty else { return .pending }
            return try values.removeFirst().get()
        }
    }

    private let code = TrackerDeviceCode(
        deviceCode: "d",
        userCode: "U",
        verificationURL: TraktAPI.activationURL,
        scanURL: TraktAPI.activationURL,
        expiresIn: 30,
        interval: 5,
    )

    @Test func `polling survives network failures and slows down when asked`() async throws {
        let sleeps = OrderRecorder()
        let session = session()
        let results = PollResults([
            .success(.pending),
            .failure(URLError(.notConnectedToInternet)),
            .success(.slowDown),
            .success(.authorized(session)),
        ])

        let received = try await TrackerDeviceAuthorizer.waitForSession(code: code, flow: PollFlow(results: results)) {
            await sleeps.append("\($0)")
        }

        #expect(received == session)
        #expect(await sleeps.values == [
            "\(Duration.seconds(5))",
            "\(Duration.seconds(5))",
            "\(Duration.seconds(5))",
            "\(Duration.seconds(10))",
        ])
    }

    @Test func `polling stops when the code expires, as simkl never reports a refusal`() async {
        await #expect(throws: TrackerAuthorizationError.expired) {
            try await TrackerDeviceAuthorizer
                .waitForSession(code: code, flow: PollFlow(results: PollResults([]))) { _ in }
        }
    }

    @Test(arguments: [
        (TrackerDevicePollResult.denied, TrackerAuthorizationError.denied),
        (.expired, .expired),
        (.missingWriteScope, .missingWriteScope),
        (.invalidClient, .invalidClient),
    ])
    func `polling ends on a final answer`(result: TrackerDevicePollResult, expected: TrackerAuthorizationError) async {
        await #expect(throws: expected) {
            try await TrackerDeviceAuthorizer.waitForSession(
                code: code,
                flow: PollFlow(results: PollResults([.success(result)])),
            ) { _ in }
        }
    }
}

actor OrderRecorder {
    private(set) var values: [String] = []

    func append(_ value: String) {
        values.append(value)
    }
}
