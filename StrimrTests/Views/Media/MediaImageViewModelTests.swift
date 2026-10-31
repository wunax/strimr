@testable import Strimr
import Testing

@MainActor
struct MediaImageViewModelTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    private func episode(seriesPoster: String? = "series-poster") -> MediaItem {
        .make(
            id: "episode-1",
            server: server,
            type: .episode,
            thumbPath: "episode-still",
            grandparentThumbPath: seriesPoster,
            grandparentArtPath: "series-backdrop",
            parentThumbPath: "season-poster",
        )
    }

    private func viewModel(_ item: MediaItem, kind: MediaImageViewModel.ArtworkKind) -> MediaImageViewModel {
        MediaImageViewModel(services: .fake(), artworkKind: kind, media: .playable(item))
    }

    @Test func `spoiler protection hides the episode image of a landscape card`() {
        let model = viewModel(episode(), kind: .cardArt)

        #expect(model.hidesSpoiler(at: .thumbnails, landscape: .episode, portrait: .series))
        #expect(!model.hidesSpoiler(at: .thumbnails, landscape: .series, portrait: .series))
    }

    @Test func `spoiler protection keeps the series poster of a portrait card`() {
        let model = viewModel(episode(), kind: .cardThumb)

        #expect(!model.hidesSpoiler(at: .thumbnails, landscape: .episode, portrait: .series))
        #expect(!model.hidesSpoiler(at: .thumbnails, landscape: .episode, portrait: .season))
    }

    @Test func `spoiler protection hides a portrait card that falls back to the episode image`() {
        let model = viewModel(episode(seriesPoster: nil), kind: .thumb)
        let item = MediaItem.make(id: "e", server: server, type: .episode, thumbPath: "episode-still")
        let fallback = viewModel(item, kind: .thumb)

        #expect(!model.hidesSpoiler(at: .thumbnails, landscape: .episode, portrait: .series))
        #expect(fallback.hidesSpoiler(at: .thumbnails, landscape: .episode, portrait: .series))
    }

    @Test func `season poster preference applies to episode and season portrait cards only`() {
        let season = MediaItem.make(id: "season-1", server: server, type: .season)
        let movie = MediaItem.make(id: "movie-1", server: server, type: .movie)

        #expect(viewModel(episode(), kind: .cardThumb).followsSeriesArtworkPreference(
            landscape: .episode,
            portrait: .season,
        ))
        #expect(viewModel(season, kind: .cardThumb).followsSeriesArtworkPreference(
            landscape: .episode,
            portrait: .season,
        ))
        #expect(!viewModel(movie, kind: .cardThumb).followsSeriesArtworkPreference(
            landscape: .series,
            portrait: .season,
        ))
        #expect(!viewModel(season, kind: .cardArt).followsSeriesArtworkPreference(
            landscape: .series,
            portrait: .season,
        ))
        #expect(!viewModel(episode(), kind: .thumb).followsSeriesArtworkPreference(
            landscape: .series,
            portrait: .season,
        ))
    }
}
