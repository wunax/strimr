import Foundation
@testable import Strimr
import Testing

@MainActor
struct PlexManagementServiceTests {
    private func options() throws -> [ArtworkOption] {
        let response = try Fixtures.decode(PlexArtworkResponse.self, from: "plex-posters")
        return PlexManagementService.artworkOptions(from: response) { URL(string: "https://server.test/preview?url=\($0)") }
    }

    @Test func `posters map to options that send their key back`() throws {
        let options = try options()

        #expect(options.map(\.source) == [
            "https://image.tmdb.org/t/p/original/poster-one.jpg",
            "https://assets.fanart.tv/fanart/movies/1/movieposter/poster-two.jpg",
            "/library/metadata/100/file?url=upload%3A%2F%2Fposters%2F0000000000000000000000000000000000000000",
        ])
        #expect(options.map(\.provider) == ["tmdb", "fanarttv", nil])
    }

    @Test func `only the selected poster is marked, whatever the flag encoding`() throws {
        #expect(try options().map(\.isSelected) == [true, false, false])
    }

    @Test func `preview uses the thumbnail, or the full image when there is none`() throws {
        let options = try options()

        #expect(options[0].previewURL.absoluteString.contains("images.plex.tv"))
        #expect(options[1].previewURL.absoluteString.hasSuffix("poster-two.jpg"))
    }

    @Test func `episodes only offer their thumbnail, stored as their poster`() {
        #expect(PlexManagementService.artworkKinds(for: .episode) == [.thumb])
        #expect(PlexManagementService.artworkElement(for: .thumb) == "poster")
        #expect(PlexManagementService.artworkKinds(for: .movie) == [.poster, .background, .logo])
        #expect(PlexManagementService.artworkKinds(for: .season) == [.poster, .background])
        #expect(PlexManagementService.artworkKinds(for: .clip).isEmpty)
    }

    @Test func `artwork kinds map to the Plex elements`() {
        #expect(PlexManagementService.artworkElement(for: .poster) == "poster")
        #expect(PlexManagementService.artworkElement(for: .background) == "art")
        #expect(PlexManagementService.artworkElement(for: .logo) == "clearLogo")
        #expect(PlexManagementService.artworkElement(for: .banner) == nil)
    }
}
