import Darwin
import Foundation

nonisolated struct JellyfinDiscoveredServer: Hashable, Identifiable, Sendable {
    let serverID: String
    let name: String
    let url: URL

    var id: String {
        serverID.isEmpty ? url.absoluteString : serverID
    }
}

nonisolated struct JellyfinServerDiscoveryService: Sendable {
    private static let discoveryPort: in_port_t = 7359
    private static let discoveryMessage = Data("Who is JellyfinServer?".utf8)
    private static let timeout: TimeInterval = 3

    func discover() async throws -> [JellyfinDiscoveredServer] {
        let task = Task.detached(priority: .userInitiated) {
            try Self.discoverSynchronously()
        }

        return try await withTaskCancellationHandler {
            try await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private static func discoverSynchronously() throws -> [JellyfinDiscoveredServer] {
        let socketDescriptor = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard socketDescriptor >= 0 else {
            throw posixError()
        }
        defer { close(socketDescriptor) }

        var enabled: Int32 = 1
        guard setsockopt(
            socketDescriptor,
            SOL_SOCKET,
            SO_BROADCAST,
            &enabled,
            socklen_t(MemoryLayout<Int32>.size),
        ) == 0 else {
            throw posixError()
        }

        var localAddress = sockaddr_in()
        localAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        localAddress.sin_family = sa_family_t(AF_INET)
        localAddress.sin_port = 0
        localAddress.sin_addr = in_addr(s_addr: INADDR_ANY)

        let bindResult = withUnsafePointer(to: &localAddress) { addressPointer in
            addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                bind(socketDescriptor, socketAddress, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bindResult == 0 else {
            throw posixError()
        }

        var broadcastAddress = sockaddr_in()
        broadcastAddress.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        broadcastAddress.sin_family = sa_family_t(AF_INET)
        broadcastAddress.sin_port = discoveryPort.bigEndian
        broadcastAddress.sin_addr = in_addr(s_addr: INADDR_BROADCAST)

        let sentByteCount = discoveryMessage.withUnsafeBytes { messageBytes in
            withUnsafePointer(to: &broadcastAddress) { addressPointer in
                addressPointer.withMemoryRebound(to: sockaddr.self, capacity: 1) { socketAddress in
                    sendto(
                        socketDescriptor,
                        messageBytes.baseAddress,
                        messageBytes.count,
                        0,
                        socketAddress,
                        socklen_t(MemoryLayout<sockaddr_in>.size),
                    )
                }
            }
        }
        guard sentByteCount == discoveryMessage.count else {
            throw posixError()
        }

        let timeoutNanoseconds = UInt64(timeout * 1_000_000_000)
        let deadline = DispatchTime.now().uptimeNanoseconds + timeoutNanoseconds
        var discoveredByID: [String: JellyfinDiscoveredServer] = [:]
        var descriptor = pollfd(fd: socketDescriptor, events: Int16(POLLIN), revents: 0)

        while true {
            try Task.checkCancellation()

            let now = DispatchTime.now().uptimeNanoseconds
            guard now < deadline else { break }
            let remainingNanoseconds = deadline - now
            let remainingMilliseconds = max(1, Int32(remainingNanoseconds / 1_000_000))
            let pollTimeout = min(remainingMilliseconds, 100)
            descriptor.revents = 0

            let pollResult = poll(&descriptor, 1, pollTimeout)
            if pollResult < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }
            guard pollResult > 0, descriptor.revents & Int16(POLLIN) != 0 else {
                continue
            }

            var buffer = [UInt8](repeating: 0, count: 65_535)
            let receivedByteCount = buffer.withUnsafeMutableBytes { bytes in
                recv(socketDescriptor, bytes.baseAddress, bytes.count, 0)
            }
            if receivedByteCount < 0 {
                if errno == EINTR { continue }
                throw posixError()
            }

            let data = Data(buffer.prefix(receivedByteCount))
            guard let server = decodeServer(from: data) else { continue }
            discoveredByID[server.id] = server
        }

        return discoveredByID.values.sorted {
            $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending
        }
    }

    private static func decodeServer(from data: Data) -> JellyfinDiscoveredServer? {
        struct Response: Decodable {
            let address: String
            let id: String?
            let name: String

            private enum CodingKeys: String, CodingKey {
                case address = "Address"
                case id = "Id"
                case name = "Name"
            }
        }

        guard let response = try? JSONDecoder().decode(Response.self, from: data),
              !response.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let url = URL(string: response.address),
              let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              components.host?.isEmpty == false
        else {
            return nil
        }

        return JellyfinDiscoveredServer(
            serverID: response.id ?? "",
            name: response.name,
            url: url,
        )
    }

    private static func posixError() -> POSIXError {
        POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
    }
}
