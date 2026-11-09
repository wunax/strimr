@testable import Strimr
import Testing

struct MediaDetailSeasonSelectionTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    private var seasons: [MediaItem] {
        [
            MediaItem.make(id: "specials", server: server, type: .season, episodeNumber: 0),
            MediaItem.make(id: "season-1", server: server, type: .season, episodeNumber: 1),
            MediaItem.make(id: "season-2", server: server, type: .season, episodeNumber: 2),
        ]
    }

    private var nextEpisode: MediaItem {
        MediaItem.make(id: "s2e1", server: server, type: .episode, seasonNumber: 2, episodeNumber: 1)
    }

    @Test func `a reload keeps the selected season`() {
        let seasonID = MediaDetailViewModel.preferredSeasonID(
            in: seasons,
            selected: "season-1",
            onDeck: nextEpisode,
            prefersOnDeckSeason: false,
        )

        #expect(seasonID == "season-1")
    }

    @Test func `a reload after playback follows the next episode into its season`() {
        let seasonID = MediaDetailViewModel.preferredSeasonID(
            in: seasons,
            selected: "season-1",
            onDeck: nextEpisode,
            prefersOnDeckSeason: true,
        )

        #expect(seasonID == "season-2")
    }

    @Test func `a reload after playback keeps the selected season when nothing is next`() {
        let seasonID = MediaDetailViewModel.preferredSeasonID(
            in: seasons,
            selected: "season-2",
            onDeck: nil,
            prefersOnDeckSeason: true,
        )

        #expect(seasonID == "season-2")
    }

    @Test func `a first load skips specials when nothing is next`() {
        let seasonID = MediaDetailViewModel.preferredSeasonID(
            in: seasons,
            selected: nil,
            onDeck: nil,
            prefersOnDeckSeason: false,
        )

        #expect(seasonID == "season-1")
    }
}
