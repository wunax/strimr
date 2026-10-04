import SwiftUI

extension ServerRegistry {
    /// Ready servers that expose Live TV, in profile order.
    var liveTVServices: [MediaServices] {
        activeSessions.compactMap(\.services).filter(\.liveTVStore.isAvailable)
    }

    /// Asks every ready server whether it exposes Live TV.
    func refreshLiveTVAvailability(force: Bool = false) async {
        await withTaskGroup(of: Void.self) { group in
            for services in activeSessions.compactMap(\.services) {
                group.addTask { @MainActor in
                    _ = await services.liveTVStore.refreshAvailability(force: force)
                }
            }
        }
    }
}

/// Live TV of one server at a time, with a server picker when several servers expose it; guides are not merged.
struct LiveTVServersView: View {
    @Environment(ServerRegistry.self) private var registry
    @State private var selectedServer: ServerIdentity?

    let onPlayLive: (LiveTVLaunchContext, MediaServices) -> Void
    let onPlayRecording: (MediaItem, MediaServices) -> Void
    let onOpenLibrary: (LibraryIdentity) -> Void

    private var servers: [MediaServices] {
        registry.liveTVServices
    }

    private var services: MediaServices? {
        servers.first { $0.identity == selectedServer } ?? servers.first
    }

    var body: some View {
        if let services {
            LiveTVView(
                store: services.liveTVStore,
                onPlayLive: { onPlayLive($0, services) },
                onPlayRecording: { onPlayRecording($0, services) },
                onOpenLibrary: { onOpenLibrary(LibraryIdentity(server: services.identity, libraryID: $0)) },
            )
            .id(services.identity)
            .environment(services)
            .safeAreaInset(edge: .top) {
                if servers.count > 1 {
                    Picker("livetv.server", selection: Binding(
                        get: { services.identity },
                        set: { selectedServer = $0 },
                    )) {
                        ForEach(servers, id: \.identity) { server in
                            Text(server.serverName).tag(server.identity)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                }
            }
        } else {
            ContentUnavailableView("livetv.unavailable", systemImage: "tv")
        }
    }
}
