import Foundation
@testable import Strimr
import Testing

@MainActor
struct MediaCopyFinderTests {
    private let plex = ServerIdentity(provider: .plex, id: "a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "b")

    @Test func `copies are sorted by resolution, then library, then server`() {
        let copies = [
            copy("hd-b", on: jellyfin, resolution: "1080", library: "1", serverName: "Beta"),
            copy("sd", on: plex, resolution: "sd", library: "1", serverName: "Alpha"),
            copy("uhd", on: plex, resolution: "4k", library: "2", serverName: "Alpha"),
            copy("hd-a2", on: plex, resolution: "1080", library: "2", serverName: "Alpha"),
            copy("hd-a1", on: plex, resolution: "1080", library: "1", serverName: "Alpha"),
        ]

        #expect(MediaCopy.sorted(copies).map(\.media.id) == ["uhd", "hd-a1", "hd-b", "hd-a2", "sd"])
    }

    private func copy(
        _ id: String,
        on server: ServerIdentity,
        resolution: String,
        library: String,
        serverName: String,
    ) -> MediaCopy {
        let base = MediaItem.make(id: id, server: server, librarySectionID: library)
        let item = MediaItem(
            id: base.id,
            identity: base.identity,
            guid: base.guid,
            summary: nil,
            title: base.title,
            type: .movie,
            parentRatingKey: nil,
            grandparentRatingKey: nil,
            genres: [],
            year: nil,
            duration: nil,
            videoResolution: resolution,
            rating: nil,
            ratings: [],
            contentRating: nil,
            studio: nil,
            tagline: nil,
            thumbPath: nil,
            artPath: nil,
            artworkCornerColors: nil,
            viewOffset: nil,
            viewCount: nil,
            childCount: nil,
            leafCount: nil,
            viewedLeafCount: nil,
            grandparentTitle: nil,
            parentTitle: nil,
            parentIndex: nil,
            index: nil,
            grandparentThumbPath: nil,
            grandparentArtPath: nil,
            parentThumbPath: nil,
            librarySectionID: library,
        )
        return MediaCopy(media: item, serverName: serverName, isReachable: true)
    }
}
