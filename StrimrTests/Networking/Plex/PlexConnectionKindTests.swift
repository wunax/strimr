import Foundation
@testable import Strimr
import Testing

struct PlexConnectionKindTests {
    private let local = URL(string: "http://192.168.1.10:32400")!
    private let remote = URL(string: "https://203-0-113-5.abc.plex.direct:32400")!
    private let relay = URL(string: "https://relay.abc.plex.direct:8443")!
    private let custom = URL(string: "https://plex.example.com")!

    private var resource: PlexCloudResource {
        PlexCloudResource(
            name: "Server",
            clientIdentifier: "server",
            accessToken: "token",
            connections: [
                connection(local, isLocal: true, isRelay: false),
                connection(remote, isLocal: false, isRelay: false),
                connection(relay, isLocal: false, isRelay: true),
            ],
        )
    }

    private func connection(_ uri: URL, isLocal: Bool, isRelay: Bool) -> PlexCloudResource.Connection {
        PlexCloudResource.Connection(
            scheme: uri.scheme ?? "https",
            address: uri.host ?? "",
            port: uri.port ?? 32400,
            uri: uri,
            isLocal: isLocal,
            isRelay: isRelay,
            isIPv6: false,
        )
    }

    @Test func `advertised connections keep their kind`() {
        #expect(PlexAPIContext.connectionKind(of: local, resource: resource, customURL: nil) == .local)
        #expect(PlexAPIContext.connectionKind(of: remote, resource: resource, customURL: nil) == .remote)
        #expect(PlexAPIContext.connectionKind(of: relay, resource: resource, customURL: nil) == .relay)
    }

    @Test func `the custom address wins over an advertised connection`() {
        #expect(PlexAPIContext.connectionKind(of: custom, resource: resource, customURL: custom) == .custom)
        #expect(PlexAPIContext.connectionKind(of: local, resource: resource, customURL: local) == .custom)
    }

    @Test func `an address plex no longer advertises is unknown`() throws {
        let stale = try #require(URL(string: "http://10.0.0.2:32400"))
        #expect(PlexAPIContext.connectionKind(of: stale, resource: resource, customURL: custom) == nil)
    }
}
