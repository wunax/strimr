import Foundation

@MainActor
final class WatchTogetherWebSocketClient {
    enum State {
        case disconnected
        case connecting
        case connected
    }

    enum ClientError: Error {
        case missingURL
        case invalidURL
    }

    var state: State = .disconnected
    var onMessage: ((WatchTogetherServerMessage) -> Void)?
    var onDisconnect: ((Error?) -> Void)?

    private var task: URLSessionWebSocketTask?
    private var receiveTask: Task<Void, Never>?
    private var pingTask: Task<Void, Never>?
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    func connect() async throws {
        guard state == .disconnected else { return }
        guard let url = watchTogetherURL() else {
            throw ClientError.missingURL
        }

        state = .connecting
        let session = URLSession(configuration: .default)
        let task = session.webSocketTask(with: url)
        self.task = task
        task.resume()
        state = .connected

        startReceiveLoop()
        startPingLoop()
    }

    func disconnect() {
        state = .disconnected
        pingTask?.cancel()
        receiveTask?.cancel()
        task?.cancel(with: .goingAway, reason: nil)
        task = nil
    }

    func send(_ message: WatchTogetherClientMessage) async throws {
        guard let task else { return }
        let data = try encoder.encode(message)
        try await task.send(.data(data))
    }

    private func startReceiveLoop() {
        receiveTask?.cancel()
        guard let task else { return }

        receiveTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                do {
                    let message = try await task.receive()
                    let data: Data
                    switch message {
                    case let .data(received):
                        data = received
                    case let .string(text):
                        guard let stringData = text.data(using: .utf8) else { continue }
                        data = stringData
                    @unknown default:
                        continue
                    }

                    let decoded = try decoder.decode(WatchTogetherServerMessage.self, from: data)
                    onMessage?(decoded)
                } catch {
                    await handleDisconnect(error)
                    return
                }
            }
        }
    }

    private func startPingLoop() {
        pingTask?.cancel()
        pingTask = Task { @MainActor [weak self] in
            while let self, !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 20_000_000_000)
                await sendPing()
            }
        }
    }

    private func sendPing() async {
        guard state == .connected else { return }
        let ping = WatchTogetherClientMessage.ping(PingRequest(sentAtMs: Self.nowMs))
        try? await send(ping)
        task?.sendPing { _ in }
    }

    private func handleDisconnect(_ error: Error?) async {
        state = .disconnected
        receiveTask?.cancel()
        pingTask?.cancel()
        task = nil
        onDisconnect?(error)
    }

    private func watchTogetherURL() -> URL? {
        guard let urlString = Bundle.main.object(forInfoDictionaryKey: "WATCH_TOGETHER_URL") as? String else {
            return nil
        }
        return URL(string: urlString)
    }

    private static var nowMs: Int64 {
        Int64(Date().timeIntervalSince1970 * 1000)
    }
}
