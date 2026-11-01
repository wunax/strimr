#if DEBUG
    import SwiftUI
    #if os(macOS)
        import AppKit
    #endif

    /// Opens the screen named by `-ScreenshotRoute` once the demo server is ready:
    /// `home`, `library:<libraryID>`, `detail:<itemID>`, `player:<itemID>` (the catalog's player item when omitted).
    @MainActor
    enum DemoRoute {
        private enum Destination {
            case home
            case library(Library)
            case media(MediaItem)
            case player(PlaybackQueue, MediaServices)
        }

        private static var isApplied = false

        static func apply(coordinator: MainCoordinator, registry: ServerRegistry) async {
            guard let destination = await destination(registry: registry) else { return }
            switch destination {
            case .home:
                coordinator.tab = .home
            case let .library(library):
                coordinator.tab = .home
                coordinator.showLibrary(library)
            case let .media(media):
                coordinator.tab = .home
                coordinator.showMediaDetail(media)
            case let .player(queue, services):
                #if os(iOS)
                    AppDelegate.orientationLock = .landscapeRight
                #endif
                coordinator.showPlayer(for: queue, services: services, shouldResumeFromOffset: false, notice: nil)
            }
        }

        #if os(macOS)
            /// App Store Mac screenshots must be 16:10; 1440×900 points is 2880×1800 pixels on a Retina display.
            static let windowSize = CGSize(width: 1440, height: 900)

            static func apply(appModel: AppModel, registry: ServerRegistry) async {
                guard let destination = await destination(registry: registry) else { return }
                switch destination {
                case .home:
                    appModel.selection = .home
                case let .library(library):
                    appModel.selection = .home
                    appModel.showLibrary(library)
                case let .media(media):
                    appModel.selection = .home
                    appModel.showMedia(media)
                case let .player(queue, services):
                    appModel.showPlayer(for: queue, services: services, shouldResumeFromOffset: false, notice: nil)
                }
                // The player opens in its own window, a moment after the route.
                try? await Task.sleep(for: .seconds(1.5))
                resizeWindows()
            }

            /// Gives every visible window the same frame, so the frontmost one is the screenshot.
            private static func resizeWindows() {
                guard let screen = NSScreen.screens.first?.visibleFrame else { return }
                let origin = CGPoint(
                    x: screen.midX - windowSize.width / 2,
                    y: screen.midY - windowSize.height / 2,
                )
                for window in NSApp.windows where window.isVisible && window.styleMask.contains(.titled) {
                    window.setFrame(CGRect(origin: origin, size: windowSize), display: true)
                }
            }
        #endif

        private static func destination(registry: ServerRegistry) async -> Destination? {
            guard DemoMode.isEnabled, !isApplied, let services = registry.services(for: DemoMode.server),
                  registry.readyServers.contains(DemoMode.server)
            else { return nil }
            isApplied = true
            #if os(tvOS)
                // Launch focus can land on the Home tab after the route switched tabs, which selects Home again.
                try? await Task.sleep(for: .seconds(1))
            #elseif os(macOS)
                // The detail column's navigation stack can still reset its path while the window first lays out.
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
                    else { return nil }
                    return .library(library)
                case "detail":
                    guard let argument else { return nil }
                    return try await .media(services.detail.mediaItem(id: argument))
                case "player":
                    guard let itemID = argument ?? (try? DemoCatalog.load(server: DemoMode.server))?.player?.item
                    else { return nil }
                    let media = try await services.detail.mediaItem(id: itemID)
                    return try await .player(services.playback.queue(startingWith: media, shuffle: false), services)
                default:
                    return .home
                }
            } catch {
                print("Demo route \(route) failed: \(error)")
                return nil
            }
        }
    }
#endif
