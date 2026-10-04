import SwiftUI

/// Shows a screen bound to one server with that server's services in the environment, or a placeholder when the
/// server is not part of the active profile anymore.
struct ServerScopedView<Content: View>: View {
    @Environment(ServerRegistry.self) private var registry

    let server: ServerIdentity?
    @ViewBuilder let content: (MediaServices) -> Content

    var body: some View {
        if let server, let services = registry.services(for: server) {
            content(services)
                .environment(services)
        } else {
            ContentUnavailableView(
                "server.unavailable.title",
                systemImage: "server.rack",
                description: Text("server.unavailable.message"),
            )
        }
    }
}

extension ServerRegistry {
    /// Services of the server an item comes from, falling back to the screen's services for the same server.
    func services(for media: MediaDisplayItem, scoped: MediaServices?) -> MediaServices? {
        services(for: media.server) ?? scoped.flatMap { $0.identity == media.server ? $0 : nil }
    }
}
