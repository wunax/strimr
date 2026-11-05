import Foundation
import Observation

/// Drives the device code sign-in of one service.
@MainActor
@Observable
final class TrackerConnectionViewModel {
    enum State: Equatable {
        case idle
        case requestingCode
        case waiting(TrackerDeviceCode)
        case finishing
        case connected
        case failed(LocalizedStringResource)
    }

    let service: TrackerService
    private(set) var state = State.idle

    @ObservationIgnored private let coordinator: TrackerCoordinator
    @ObservationIgnored private let flow: any TrackerDeviceFlow
    @ObservationIgnored private var task: Task<Void, Never>?

    init(service: TrackerService, coordinator: TrackerCoordinator, flow: (any TrackerDeviceFlow)? = nil) {
        self.service = service
        self.coordinator = coordinator
        self.flow = flow ?? Self.defaultFlow(for: service)
    }

    private static func defaultFlow(for service: TrackerService) -> any TrackerDeviceFlow {
        switch service {
        case .trakt: TraktDeviceFlow()
        case .simkl: SimklDeviceFlow()
        }
    }

    func start() {
        task?.cancel()
        state = .requestingCode
        task = Task { await run() }
    }

    func cancel() {
        task?.cancel()
        task = nil
        if state != .connected {
            state = .idle
        }
    }

    private func run() async {
        do {
            let code = try await flow.requestCode()
            state = .waiting(code)
            let session = try await TrackerDeviceAuthorizer.waitForSession(code: code, flow: flow)
            guard !Task.isCancelled else { return }
            state = .finishing
            await coordinator.connect(service, session: session)
            state = .connected
        } catch {
            guard !Task.isCancelled, !error.isCancellation else { return }
            state = .failed(message(for: error))
        }
    }

    private func message(for error: Error) -> LocalizedStringResource {
        switch error as? TrackerAuthorizationError {
        case .expired:
            return "integrations.trackers.connect.error.expired"
        case .denied:
            return "integrations.trackers.connect.error.denied"
        case .missingWriteScope:
            return "integrations.trackers.connect.error.permissions"
        case .invalidClient:
            ErrorReporter.capture(error)
            return "integrations.trackers.connect.error.generic"
        case nil:
            if !error.isTrackerTransient {
                ErrorReporter.capture(error)
            }
            return "integrations.trackers.connect.error.generic"
        }
    }
}
