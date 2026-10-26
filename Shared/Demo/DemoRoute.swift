#if DEBUG
    import SwiftUI

    /// Opens the screen named by `-ScreenshotRoute` once the demo server is ready:
    /// `home`, `library:<libraryID>`, `detail:<itemID>`, `player:<itemID>` (the catalog's player item when omitted).
    @MainActor
    enum DemoRoute {
        private static var isApplied = false

        static func apply(coordinator: MainCoordinator, registry: ServerRegistry) async {
            guard DemoMode.isEnabled, !isApplied, let services = registry.services(for: DemoMode.server),
                  registry.readyServers.contains(DemoMode.server)
            else { return }
            isApplied = true
            #if os(tvOS)
                // Launch focus can land on the Home tab after the route switched tabs, which selects Home again.
                try? await Task.sleep(for: .seconds(1))
            #endif
            let route = DemoMode.route ?? "home"
            let name = route.prefix { $0 != ":" }
            let argument = route.contains(":") ? String(route.drop { $0 != ":" }.dropFirst()) : nil

            do {
                switch name {
                case "library":
                    guard let argument,
                          let library = try await services.library.libraries().first(where: { $0.id == argument })
                    else { return }
                    coordinator.tab = .library
                    coordinator.libraryPath.append(library)
                case "detail":
                    guard let argument else { return }
                    let media = try await services.detail.mediaItem(id: argument)
                    coordinator.tab = .home
                    coordinator.showMediaDetail(media)
                case "player":
                    guard let itemID = argument ?? (try? DemoCatalog.load(server: DemoMode.server))?.player?.item
                    else { return }
                    let media = try await services.detail.mediaItem(id: itemID)
                    let queue = try await services.playback.queue(startingWith: media, shuffle: false)
                    #if os(iOS)
                        AppDelegate.orientationLock = .landscapeRight
                    #endif
                    coordinator.showPlayer(for: queue, services: services, shouldResumeFromOffset: false, notice: nil)
                default:
                    coordinator.tab = .home
                }
            } catch {
                print("Demo route \(route) failed: \(error)")
            }
        }
    }
#endif
