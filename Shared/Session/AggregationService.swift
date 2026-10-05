import Foundation

/// Sends the same request to several servers in parallel. A failing server never fails the whole request: it is
/// reported in the result and the other servers' values are kept.
@MainActor
final class AggregationService {
    private let reportTransportFailure: (ServerIdentity) -> Void
    private let captureError: (Error) -> Void

    init(
        reportTransportFailure: @escaping (ServerIdentity) -> Void,
        captureError: @escaping (Error) -> Void = { ErrorReporter.capture($0) },
    ) {
        self.reportTransportFailure = reportTransportFailure
        self.captureError = captureError
    }

    /// Queries every ready and enabled server; the others, and those without the capability, are `skipped`.
    func fanOut<T: Sendable>(
        servers: [ServerSession],
        supports: (MediaServices) -> Bool = { _ in true },
        _ fetch: @escaping (MediaServices) async throws -> T,
    ) async -> Aggregated<[ServerIdentity: T]> {
        await fanOut(
            targets: servers,
            identity: \.identity,
            services: { session in
                guard session.isActive, let services = session.services, supports(services) else { return nil }
                return services
            },
            fetch,
        )
    }

    func fanOut<Target, Service, T: Sendable>(
        targets: [Target],
        identity: (Target) -> ServerIdentity,
        services: (Target) -> Service?,
        _ fetch: @escaping (Service) async throws -> T,
    ) async -> Aggregated<[ServerIdentity: T]> {
        var result = Aggregated<[ServerIdentity: T]>(value: [:])
        var eligible: [(ServerIdentity, Service)] = []
        for target in targets {
            let server = identity(target)
            if let service = services(target) {
                eligible.append((server, service))
            } else {
                result.skipped.insert(server)
            }
        }

        let outcomes = await withTaskGroup(of: (ServerIdentity, Result<T, Error>).self) { group in
            for (server, service) in eligible {
                group.addTask { @MainActor in
                    do {
                        return try await (server, .success(fetch(service)))
                    } catch {
                        return (server, .failure(error))
                    }
                }
            }
            var outcomes: [(ServerIdentity, Result<T, Error>)] = []
            for await outcome in group {
                outcomes.append(outcome)
            }
            return outcomes
        }

        let isCancelled = Task.isCancelled
        for (server, outcome) in outcomes {
            switch outcome {
            case let .success(value):
                result.value[server] = value
                result.succeeded.insert(server)
            case let .failure(error):
                if isCancelled || error.isCancellation {
                    result.cancelled.insert(server)
                } else if error.isTransportFailure {
                    result.failed.insert(server)
                    reportTransportFailure(server)
                } else {
                    result.failed.insert(server)
                    captureError(error)
                }
            }
        }
        return result
    }
}
