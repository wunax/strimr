@testable import Strimr
import Testing

struct ExploreSourceRegistryTests {
    @Test func `the user's pick wins while it is connected`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .trakt, connected: [.seerr, .trakt]) == .trakt)
    }

    @Test func `Seerr comes first by default so the former Discover tab looks the same`() {
        #expect(ExploreSourceRegistry
            .resolveActive(preferred: nil, connected: [.simkl, .trakt, .plex, .seerr]) == .seerr)
        #expect(ExploreSourceRegistry.resolveActive(preferred: nil, connected: [.simkl, .trakt, .plex]) == .plex)
        #expect(ExploreSourceRegistry.resolveActive(preferred: nil, connected: [.simkl, .trakt]) == .trakt)
    }

    @Test func `a disconnected pick falls back to the priority order`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .simkl, connected: [.plex, .trakt]) == .plex)
    }

    @Test func `no source leaves nothing active`() {
        #expect(ExploreSourceRegistry.resolveActive(preferred: .plex, connected: []) == nil)
    }
}
