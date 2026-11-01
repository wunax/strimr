import Foundation
@testable import Strimr
import Testing

@MainActor
struct JellyfinManagementServiceTests {
    private func remoteImages() throws -> [JellyfinRemoteImage] {
        try Fixtures.decode(JellyfinRemoteImageResult.self, from: "jellyfin-remote-images").images ?? []
    }

    private func currentImages() throws -> [JellyfinImageInfo] {
        try Fixtures.decode([JellyfinImageInfo].self, from: "jellyfin-item-images")
    }

    @Test func `remote images map to options without duplicates`() throws {
        let options = try JellyfinManagementService.artworkOptions(
            from: remoteImages(),
            current: [],
            imageType: "Primary",
        )

        #expect(options.map(\.source) == [
            "https://image.tmdb.org/t/p/original/poster-en.jpg",
            "https://image.tmdb.org/t/p/original/poster-fr.jpg",
            "https://artworks.thetvdb.com/banners/movies/1/posters/poster-none.jpg",
        ])
        #expect(options.map(\.language) == ["en", "fr", nil])
        #expect(options.map(\.provider) == ["TheMovieDb", "TheMovieDb", "TheTVDB"])
        #expect(options.allSatisfy { !$0.isSelected })
    }

    @Test func `preview uses the thumbnail, or the full image when there is none`() throws {
        let options = try JellyfinManagementService.artworkOptions(
            from: remoteImages(),
            current: [],
            imageType: "Primary",
        )

        #expect(options[0].previewURL.absoluteString == "https://image.tmdb.org/t/p/w500/poster-en.jpg")
        #expect(options[2].previewURL.absoluteString.hasSuffix("poster-none.jpg"))
    }

    @Test func `current image is recognized by its size`() throws {
        let options = try JellyfinManagementService.artworkOptions(
            from: remoteImages(),
            current: currentImages(),
            imageType: "Primary",
        )

        #expect(options.map(\.isSelected) == [false, true, false])
    }

    @Test func `nothing is marked when several images share the current size`() throws {
        let current = [JellyfinImageInfo(imageType: "Primary", imageIndex: nil, width: 1000, height: 1500)]
        let images = try remoteImages() + [JellyfinRemoteImage(
            providerName: "TheTVDB",
            url: "https://artworks.thetvdb.com/banners/movies/1/posters/same-size.jpg",
            thumbnailURL: nil,
            width: 1000,
            height: 1500,
            language: "fr",
        )]

        let options = JellyfinManagementService.artworkOptions(from: images, current: current, imageType: "Primary")

        #expect(options.allSatisfy { !$0.isSelected })
    }

    @Test func `only the image of the listed type is compared`() throws {
        let options = try JellyfinManagementService.artworkOptions(
            from: remoteImages(),
            current: currentImages(),
            imageType: "Backdrop",
        )

        #expect(options.allSatisfy { !$0.isSelected })
    }

    @Test func `an episode thumbnail is its primary image`() {
        #expect(JellyfinManagementService.artworkKinds(for: .episode) == [.thumb])
        #expect(JellyfinManagementService.imageType(for: .thumb, itemType: .episode) == "Primary")
        #expect(JellyfinManagementService.imageType(for: .thumb, itemType: .movie) == "Thumb")
        #expect(JellyfinManagementService.imageType(for: .background, itemType: .series) == "Backdrop")
        #expect(JellyfinManagementService.artworkKinds(for: .movie) == [.poster, .background, .logo, .thumb, .banner])
        #expect(JellyfinManagementService.artworkKinds(for: .season) == [.poster, .background])
    }
}
