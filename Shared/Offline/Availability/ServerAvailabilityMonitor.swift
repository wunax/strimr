import Foundation
import Network
import Observation

/// Tracks reachability per server by combining the network path, transport failures reported by service calls and a
/// lightweight probe with exponential backoff while a server is unreachable.
@MainActor
@Observable
final class ServerAvailabilityMonitor {
    typealias Probe = @MainActor () async -> Bool

    private(set) var availabilities: [ServerIdentity: ServerAvailability] = [:]
    private(set) var hasNetworkPath = true

    @ObservationIgnored var onServerBecameReachable: ((ServerIdentity) -> Void)?
    @ObservationIgnored var onNetworkPathRestored: (() -> Void)?
    @ObservationIgnored private var probes: [ServerIdentity: Probe] = [:]
    @ObservationIgnored private var probeTasks: [ServerIdentity: Task<Void, Never>] = [:]
    @ObservationIgnored private let pathMonitor = NWPathMonitor()
    @ObservationIgnored private let pathQueue = DispatchQueue(label: "strimr.offline.path-monitor")

    private static let initialBackoff: Duration = .seconds(2)
    private static let maximumBackoff: Duration = .seconds(60)

    init() {
        pathMonitor.pathUpdateHandler = { [weak self] path in
            guard let self else { return }
            let isSatisfied = path.status == .satisfied
            Task { @MainActor in
                self.handlePathUpdate(isSatisfied: isSatisfied)
            }
        }
        pathMonitor.start(queue: pathQueue)
    }

    func availability(for server: ServerIdentity) -> ServerAvailability {
        availabilities[server] ?? .unknown
    }

    func isUnreachable(_ server: ServerIdentity) -> Bool {
        availability(for: server).isUnreachable
    }

    /// Starts tracking a server of the session. `probe` returns `true` when the server answers.
    func track(_ server: ServerIdentity, probe: @escaping Probe) {
        probes[server] = probe
        if availabilities[server] == nil {
            availabilities[server] = hasNetworkPath ? .unknown : .unreachable(since: Date())
        }
        if hasNetworkPath {
            startProbing(server, initialDelay: .zero)
        }
    }

    func untrack(_ server: ServerIdentity) {
        probes[server] = nil
        probeTasks.removeValue(forKey: server)?.cancel()
        availabilities[server] = nil
    }

    func untrackAll() {
        for server in Array(probes.keys) {
            untrack(server)
        }
    }

    /// Called by service decorators when a request failed at the transport level (timeout, refused connection…).
    func reportTransportFailure(on server: ServerIdentity) {
        guard probes[server] != nil else { return }
        markUnreachable(server)
        startProbing(server, initialDelay: Self.initialBackoff)
    }

    /// Called when a request to the server succeeded.
    func reportSuccess(on server: ServerIdentity) {
        guard probes[server] != nil else { return }
        markReachable(server)
    }

    /// Re-probes unreachable servers, e.g. when the app comes back to the foreground.
    func refresh() {
        for (server, availability) in availabilities where availability != .reachable {
            startProbing(server, initialDelay: .zero)
        }
    }

    private func handlePathUpdate(isSatisfied: Bool) {
        let wasSatisfied = hasNetworkPath
        hasNetworkPath = isSatisfied
        if !isSatisfied {
            for server in probes.keys {
                probeTasks.removeValue(forKey: server)?.cancel()
                markUnreachable(server)
            }
            return
        }
        if !wasSatisfied {
            onNetworkPathRestored?()
        }
        for server in probes.keys {
            startProbing(server, initialDelay: .zero)
        }
    }

    private func startProbing(_ server: ServerIdentity, initialDelay: Duration) {
        guard let probe = probes[server], hasNetworkPath else { return }
        probeTasks[server]?.cancel()
        probeTasks[server] = Task { [weak self] in
            var delay = initialDelay
            while !Task.isCancelled {
                if delay > .zero {
                    try? await Task.sleep(for: delay)
                }
                guard !Task.isCancelled else { return }
                if await probe() {
                    guard !Task.isCancelled else { return }
                    self?.markReachable(server)
                    self?.probeTasks[server] = nil
                    return
                }
                guard !Task.isCancelled else { return }
                self?.markUnreachable(server)
                delay = delay == .zero ? Self.initialBackoff : min(delay * 2, Self.maximumBackoff)
            }
        }
    }

    private func markReachable(_ server: ServerIdentity) {
        let previous = availabilities[server]
        guard previous != .reachable else { return }
        availabilities[server] = .reachable
        probeTasks.removeValue(forKey: server)?.cancel()
        onServerBecameReachable?(server)
    }

    private func markUnreachable(_ server: ServerIdentity) {
        guard !(availabilities[server]?.isUnreachable ?? false) else { return }
        availabilities[server] = .unreachable(since: Date())
    }

    /// Plex answers `/identity` without authentication; Jellyfin exposes `/System/Info/Public`.
    static func probe(url makeURL: @escaping @MainActor () -> URL?) -> Probe {
        {
            guard let url = makeURL() else { return false }
            var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 5)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            do {
                let (_, response) = try await URLSession.shared.data(for: request)
                guard let status = (response as? HTTPURLResponse)?.statusCode else { return false }
                return (200 ..< 500).contains(status)
            } catch {
                return false
            }
        }
    }
}
