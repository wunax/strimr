import Foundation

/// Runs writes one at a time, a minimum gap apart: both services allow one write per second per user, and Simkl may
/// suspend an app that keeps exceeding it.
@MainActor
final class TrackerWriteGate {
    typealias Sleep = @Sendable (Duration) async throws -> Void

    private let spacing: Duration
    private let sleep: Sleep
    private var tail: Task<Void, Never>?

    init(spacing: Duration = .seconds(1), sleep: @escaping Sleep = { try await Task.sleep(for: $0) }) {
        self.spacing = spacing
        self.sleep = sleep
    }

    func run<T: Sendable>(_ operation: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = tail
        let task = Task<T, Error> { @MainActor in
            await previous?.value
            return try await operation()
        }
        let spacing = spacing
        let sleep = sleep
        tail = Task {
            _ = await task.result
            try? await sleep(spacing)
        }
        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }
}

/// Owns a session's tokens: hands out a valid access token and renews it close to expiry or after a rejection, with
/// concurrent renewals merged into one because Trakt's refresh tokens work only once.
@MainActor
final class TrackerTokenProvider {
    typealias Refresh = @MainActor (TrackerSession) async throws -> TrackerSession

    private static let refreshMargin: TimeInterval = 60 * 60

    private(set) var session: TrackerSession
    private let refresh: Refresh
    private let onUpdated: (TrackerSession) -> Void
    private let onInvalidated: () -> Void
    private let now: () -> Date
    private var refreshTask: Task<TrackerSession, Error>?

    init(
        session: TrackerSession,
        refresh: @escaping Refresh,
        onUpdated: @escaping (TrackerSession) -> Void,
        onInvalidated: @escaping () -> Void,
        now: @escaping () -> Date = Date.init,
    ) {
        self.session = session
        self.refresh = refresh
        self.onUpdated = onUpdated
        self.onInvalidated = onInvalidated
        self.now = now
    }

    func validAccessToken() async throws -> String {
        guard session.expiresAt.timeIntervalSince(now()) < Self.refreshMargin else { return session.accessToken }
        do {
            return try await renew().accessToken
        } catch let error as TrackerAPIError where error == .sessionExpired {
            throw error
        } catch {
            guard !error.isCancellation else { throw error }
            // The current token still works until it actually expires.
            guard session.expiresAt > now() else { throw error }
            return session.accessToken
        }
    }

    func accessToken(afterRejecting rejected: String) async throws -> String {
        // Another request may have renewed it while this one was in flight.
        guard session.accessToken == rejected else { return session.accessToken }
        return try await renew().accessToken
    }

    private func renew() async throws -> TrackerSession {
        if let refreshTask {
            return try await refreshTask.value
        }
        let current = session
        let task = Task<TrackerSession, Error> { @MainActor in
            defer { refreshTask = nil }
            do {
                let renewed = try await refresh(current)
                // Saved before any other use: the previous refresh token no longer works.
                session = renewed
                onUpdated(renewed)
                return renewed
            } catch let error as TrackerAPIError where error == .sessionExpired {
                onInvalidated()
                throw error
            }
        }
        refreshTask = task
        return try await task.value
    }
}

/// Sends authorized requests: attaches the token, retries once after a renewal on a 401, and maps failures.
@MainActor
final class TrackerTransport {
    typealias ErrorMapper = @Sendable (TrackerHTTPResponse) -> TrackerAPIError

    let tokens: TrackerTokenProvider
    private let http: TrackerHTTP
    private let gate: TrackerWriteGate
    private let mapError: ErrorMapper

    init(tokens: TrackerTokenProvider, http: TrackerHTTP, gate: TrackerWriteGate, mapError: @escaping ErrorMapper) {
        self.tokens = tokens
        self.http = http
        self.gate = gate
        self.mapError = mapError
    }

    func read(_ build: @escaping (String) -> URLRequest) async throws -> TrackerHTTPResponse {
        try await send(build)
    }

    @discardableResult
    func write(_ build: @escaping (String) -> URLRequest) async throws -> TrackerHTTPResponse {
        try await gate.run { [self] in
            try await send(build)
        }
    }

    private func send(_ build: (String) -> URLRequest) async throws -> TrackerHTTPResponse {
        let token = try await tokens.validAccessToken()
        var response = try await http.send(build(token))
        if response.statusCode == 401 {
            let renewed = try await tokens.accessToken(afterRejecting: token)
            response = try await http.send(build(renewed))
        }
        guard response.isSuccess else { throw mapError(response) }
        return response
    }
}

nonisolated enum TrackerDevicePollResult: Equatable, Sendable {
    case pending
    case slowDown
    case expired
    case denied
    case missingWriteScope
    case invalidClient
    case authorized(TrackerSession)
}

nonisolated struct TrackerDeviceCode: Equatable, Sendable {
    let deviceCode: String
    let userCode: String
    let verificationURL: URL
    /// Shown as a QR code; carries the code when the service supports it.
    let scanURL: URL
    let expiresIn: TimeInterval
    let interval: TimeInterval
}

@MainActor
protocol TrackerDeviceFlow {
    func requestCode() async throws -> TrackerDeviceCode
    func poll(_ code: TrackerDeviceCode) async throws -> TrackerDevicePollResult
}

nonisolated enum TrackerAuthorizationError: Error, Equatable {
    case expired
    case denied
    case missingWriteScope
    case invalidClient
}

enum TrackerDeviceAuthorizer {
    /// Polls at the service's pace until the user answers or the code expires. A network failure does not end the
    /// wait: the code stays valid, and the user may be about to approve it.
    static func waitForSession(
        code: TrackerDeviceCode,
        flow: any TrackerDeviceFlow,
        sleep: @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
    ) async throws -> TrackerSession {
        var interval = max(code.interval, 1)
        var elapsed: TimeInterval = 0
        while elapsed < code.expiresIn {
            try await sleep(.seconds(interval))
            elapsed += interval
            let result: TrackerDevicePollResult
            do {
                result = try await flow.poll(code)
            } catch {
                guard !error.isCancellation else { throw error }
                continue
            }
            switch result {
            case .pending:
                continue
            case .slowDown:
                interval += 5
            case .expired:
                throw TrackerAuthorizationError.expired
            case .denied:
                throw TrackerAuthorizationError.denied
            case .missingWriteScope:
                throw TrackerAuthorizationError.missingWriteScope
            case .invalidClient:
                throw TrackerAuthorizationError.invalidClient
            case let .authorized(session):
                return session
            }
        }
        throw TrackerAuthorizationError.expired
    }
}
