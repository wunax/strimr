import Foundation
@testable import Strimr
import Testing

struct JellyfinMappingTests {
    private let server = ServerIdentity(provider: .jellyfin, id: "server-1")

    @Test func `maps movie`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-movie")
        let media = MediaItem(jellyfinItem: item, server: server)

        #expect(media.id == "movie-1")
        #expect(media.identity == MediaIdentity(server: server, itemID: "movie-1"))
        #expect(media.guid == "jellyfin://server-1/movie-1")
        #expect(media.type == .movie)
        #expect(media.year == 2021)
        #expect(media.releaseDate == ISO8601DateFormatter().date(from: "2021-06-18T00:00:00Z"))
        #expect(media.duration == 7200)
        #expect(media.genres == ["Drama", "Thriller"])
        #expect(media.studio == "Example Studio")
        #expect(media.tagline == "The tagline.")
        #expect(media.contentRating == "PG-13")
        #expect(media.ratings == [
            MediaRating(source: .jellyfinCommunity, value: 7.4),
            MediaRating(source: .jellyfinCritics, value: 88),
        ])
        #expect(media.thumbPath == "jellyfin-artwork://movie-1/Primary?tag=primary-tag")
        #expect(media.artPath == "jellyfin-artwork://movie-1/Backdrop?tag=backdrop-tag")
        #expect(media.viewOffset == 600)
        #expect(media.viewCount == 0)
        #expect(media.watchState == MediaWatchState(
            isPlayed: false,
            playCount: 0,
            resumePosition: 600,
            unplayedItemCount: nil,
            isFavorite: true,
        ))
        #expect(media.lastViewedAt == ISO8601DateFormatter().date(from: "2026-03-14T20:15:30Z"))
    }

    @Test func `maps episode`() throws {
        let item = try Fixtures.decode(JellyfinItem.self, from: "jellyfin-episode")
        let media = MediaItem(jellyfinItem: item, server: server)

        #expect(media.type == .episode)
        #expect(media.parentRatingKey == "season-1")
        #expect(media.grandparentRatingKey == "series-1")
        #expect(media.grandparentTitle == "Example Show")
        #expect(media.parentTitle == "Season 1")
        #expect(media.parentIndex == 1)
        #expect(media.index == 1)
        #expect(media.thumbPath == nil)
        #expect(media.artPath == nil)
        #expect(media.grandparentThumbPath == "jellyfin-artwork://series-1/Primary?tag=series-tag")
        #expect(media.viewOffset == nil)
        // Jellyfin can report Played with a PlayCount of 0; the mapping still counts one view.
        #expect(media.viewCount == 1)
        #expect(media.watchState.isPlayed)
    }

    @Test func `maps display items by kind`() throws {
        let result = try Fixtures.decode(JellyfinQueryResult<JellyfinItem>.self, from: "jellyfin-items")
        let items = result.items.map { MediaDisplayItem(jellyfinItem: $0, server: server) }

        try #require(items.count == 4)

        guard case let .collection(collection) = items[0] else {
            Issue.record("Expected a collection, got \(String(describing: items[0]))")
            return
        }
        #expect(collection.childCount == 3)
        #expect(collection.thumbPath == "jellyfin-artwork://boxset-1/Primary?tag=boxset-tag")

        guard case let .playlist(playlist) = items[1] else {
            Issue.record("Expected a playlist, got \(String(describing: items[1]))")
            return
        }
        #expect(playlist.duration == 9_000_000)
        #expect(playlist.leafCount == 12)

        #expect(items[2] == nil)

        guard case let .playable(trailer) = items[3] else {
            Issue.record("Expected a playable item, got \(String(describing: items[3]))")
            return
        }
        #expect(trailer.type == .clip)
    }

    @Test(arguments: [
        ("tvshows", MediaKind.series),
        ("TvShows", .series),
        ("boxsets", .collection),
        ("playlists", .playlist),
        ("movies", .movie),
        ("homevideos", .movie),
    ])
    func `maps library type`(collectionType: String, expected: MediaKind) throws {
        let json = #"{"Id":"lib","Name":"Library","CollectionType":"\#(collectionType)"}"#
        let item = try JSONDecoder().decode(JellyfinItem.self, from: Data(json.utf8))

        #expect(Library(jellyfinItem: item, server: server).type == expected)
    }

    @Test(arguments: [
        (
            #"{"Index":2,"Type":"Audio","DisplayTitle":"English - AAC","Title":"Main","Language":"eng","Codec":"aac"}"#,
            "English - AAC",
        ),
        (#"{"Index":2,"Type":"Audio","Title":"Main","Language":"eng","Codec":"aac"}"#, "Main"),
        (#"{"Index":2,"Type":"Audio","Language":"eng","Codec":"aac"}"#, "eng"),
        (#"{"Index":2,"Type":"Audio","Codec":"aac"}"#, "aac"),
        (#"{"Index":2,"Type":"Audio"}"#, ""),
    ])
    func `track display title falls back`(json: String, expected: String) throws {
        let stream = try JSONDecoder().decode(JellyfinMediaStream.self, from: Data(json.utf8))
        let track = MediaTrackMetadata(jellyfinStream: stream)

        #expect(track.displayTitle == expected)
        #expect(track.id == 2)
        #expect(track.sourceIndex == 2)
        #expect(!track.isDefault)
        #expect(!track.isForced)
    }

    @Test func `chapter artwork path round trips`() throws {
        let path = JellyfinArtworkPath.makeChapter(ownerID: "movie-1", index: 4, tag: "chapter-tag")
        let parsed = try #require(JellyfinArtworkPath.parse(path))

        #expect(parsed.ownerID == "movie-1")
        #expect(parsed.type == "Chapter")
        #expect(parsed.index == 4)
        #expect(parsed.tag == "chapter-tag")
    }

    @Test func `artwork path requires tag`() {
        #expect(JellyfinArtworkPath.make(ownerID: "movie-1", type: "Primary", tag: nil) == nil)
        #expect(JellyfinArtworkPath.parse("https://example.com/image") == nil)
    }
}
