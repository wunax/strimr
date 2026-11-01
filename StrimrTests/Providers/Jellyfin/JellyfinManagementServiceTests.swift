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

    @Test func `deleting a movie counts the files of every version`() throws {
        let movie = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-deletion-movie")

        #expect(movie.canDelete == true)
        #expect(JellyfinManagementService.deletionImpact(of: movie, episodeCount: nil)
            == .files(count: 2, totalSize: 17_000_000_000))
    }

    @Test func `deleting a series counts its episodes, falling back to its descendants`() throws {
        let series = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-deletion-series")

        #expect(series.canDelete == false)
        #expect(JellyfinManagementService.deletionImpact(of: series, episodeCount: 24) == .episodes(count: 24))
        #expect(JellyfinManagementService.deletionImpact(of: series, episodeCount: nil) == .episodes(count: 26))
    }

    private func candidates(current: ExternalIDs = ExternalIDs()) throws -> [MatchCandidate] {
        try JellyfinManagementService.matchCandidates(from: Fixtures.data("jellyfin-remote-search"), current: current)
    }

    @Test func `search results map to candidates once per provider and title`() throws {
        let candidates = try candidates()

        #expect(candidates.map(\.title) == ["Sample Movie", "Sample Movie Returns", "Sample Movie"])
        #expect(candidates.map(\.year) == [2010, 2014, 2010])
        #expect(candidates.map(\.provider) == ["TheMovieDb", "TheMovieDb", "The Open Movie Database"])
        #expect(candidates[0].posterURL?.absoluteString == "https://image.tmdb.org/t/p/original/sample-one.jpg")
        #expect(candidates[1].posterURL == nil)
    }

    @Test func `the current match shares a provider id with the item`() throws {
        let candidates = try candidates(current: ExternalIDs(imdb: "tt0000001", tmdb: "1001"))

        #expect(candidates.map(\.isCurrent) == [true, false, true])
        #expect(try self.candidates().allSatisfy { !$0.isCurrent })
    }

    @Test func `the search result is sent back with every field the server returned`() throws {
        guard case let .jellyfin(payload) = try candidates()[0].payload else {
            Issue.record("Expected a Jellyfin payload")
            return
        }
        let result = try #require(try JSONSerialization.jsonObject(with: payload) as? [String: Any])

        #expect(result["Overview"] as? String == "A sample overview.")
        #expect(result["SearchProviderName"] as? String == "TheMovieDb")
        #expect((result["ProviderIds"] as? [String: String])?["Tmdb"] == "1001")
        #expect(result["Artists"] as? [Any] != nil)
    }

    @Test func `only movies and series can be identified`() {
        #expect(JellyfinManagementService.remoteSearchType(for: .movie) == "Movie")
        #expect(JellyfinManagementService.remoteSearchType(for: .series) == "Series")
        #expect(JellyfinManagementService.remoteSearchType(for: .episode) == nil)
    }
}
