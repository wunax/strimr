import Foundation

final class UserRepository {
    private let network: PlexCloudNetworkClient
    private weak var context: PlexAPIContext?

    init(context: PlexAPIContext) {
        self.context = context
        network = PlexCloudNetworkClient(authToken: context.authTokenCloud, clientIdentifier: context.clientIdentifier)
    }

    func getUser() async throws -> PlexCloudUser {
        try await network.request(path: "/user", method: "GET")
    }

    func getHomeUsers() async throws -> PlexHome {
        try await network.request(path: "/home/users", method: "GET")
    }

    func switchUser(uuid: String, pin: String?) async throws -> PlexCloudUser {
        struct SwitchRequest: Codable {
            let pin: String
        }

        var headers: [String: String] = [:]
        var body: Data?

        if let pin, !pin.isEmpty {
            headers["Content-Type"] = "application/json"
            body = try JSONEncoder().encode(SwitchRequest(pin: pin))
        }

        return try await network.request(
            path: "/home/users/\(uuid)/switch",
            method: "POST",
            headers: headers,
            body: body,
        )
    }
}
