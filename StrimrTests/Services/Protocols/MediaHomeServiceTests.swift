import Foundation
@testable import Strimr
import Testing

@MainActor
struct MediaHomeServiceTests {
    private final class HomeOnlyService: MediaHomeService {
        let server = ServerIdentity(provider: .plex, id: "plex-a")
        var hiddenLibraryIDs: Set<String>?

        func loadHome(
            hiddenLibraryIDs: Set<String>,
            includesPlaylists _: Bool,
            shownRowIDs _: Set<String>,
        ) async throws -> HomeContent {
            self.hiddenLibraryIDs = hiddenLibraryIDs
            return HomeContent(rows: [
                .continueWatching(server: server, hub: hub("continue")),
                .providerHub(server: server, hub: hub("movie.recentlyadded.1")),
                .nextUp(server: server, hub: hub("nextUp")),
            ])
        }

        func items(in _: Hub, startIndex _: Int, limit _: Int) async throws -> MediaPage<MediaDisplayItem> {
            MediaPage(items: [], startIndex: 0, totalCount: 0)
        }

        private func hub(_ id: String) -> Hub {
            Hub.make(id: id, title: id, items: [MediaItem.make(id: "\(id)-1", server: server)], server: server)
        }
    }

    @Test func `without a dedicated request, the watching rows come from the whole home`() async throws {
        let service = HomeOnlyService()

        let rows = try await service.loadWatchingRows(hiddenLibraryIDs: ["2"])

        #expect(rows.map(\.kind) == [.continueWatching, .nextUp])
        #expect(service.hiddenLibraryIDs == ["2"])
    }
}
