import Foundation
@testable import Strimr
import Testing

struct DeepLinkTests {
    private let plex = ServerIdentity(provider: .plex, id: "server-a")
    private let jellyfin = ServerIdentity(provider: .jellyfin, id: "server-b")

    private func link(_ string: String) -> DeepLink? {
        URL(string: string).flatMap(DeepLink.init(url:))
    }

    @Test func `every destination reads back from its url`() {
        let links = [
            DeepLink(.open),
            DeepLink(.open, profile: "local.kids"),
            DeepLink(.media(.item(MediaIdentity(server: jellyfin, itemID: "abc"), kind: .episode))),
            DeepLink(.media(.item(MediaIdentity(server: plex, itemID: "42"), kind: nil))),
            DeepLink(.media(.catalog(.init(
                kind: .movie,
                ids: ExternalIDs(tmdb: "278"),
                title: "Les Évadés",
                year: 1994,
            )))),
            DeepLink(.play(.item(MediaIdentity(server: plex, itemID: "42"), kind: .movie), mode: .resume)),
            DeepLink(.play(.item(MediaIdentity(server: plex, itemID: "42"), kind: .series), mode: .shuffle)),
            DeepLink(.play(.catalog(.init(kind: .show, ids: ExternalIDs(tvdb: "81189"))), mode: .restart)),
            DeepLink(.play(
                .item(MediaIdentity(server: jellyfin, itemID: "abc"), kind: .movie),
                mode: .resume,
                options: PlaybackStartOptions(offset: 1800, audioLanguage: "ja", subtitles: .language("en")),
            )),
            DeepLink(.play(
                .catalog(.init(kind: .movie, ids: ExternalIDs(tmdb: "278"))),
                mode: .restart,
                options: PlaybackStartOptions(offset: 90.5, subtitles: .off),
            )),
            DeepLink(.liveChannel("TF1", server: nil)),
            DeepLink(.liveChannel("/channels/12", server: jellyfin)),
            DeepLink(.library(LibraryIdentity(server: plex, libraryID: "3"))),
            DeepLink(.search(nil)),
            DeepLink(.search("Rock & Roll + more")),
            DeepLink(.tab(.liveTV), profile: "Anna"),
        ]
        for link in links {
            #expect(DeepLink(url: link.url) == link, "\(link.url)")
        }
    }

    @Test func `top shelf links keep working`() {
        #expect(link("strimr://media/42?type=show&server=s1") == DeepLink(.media(.item(
            MediaIdentity(server: ServerIdentity(provider: .plex, id: "s1"), itemID: "42"),
            kind: .series,
        ))))
        #expect(link("strimr://play/abc?type=Movie&provider=jellyfin&server=s2") == DeepLink(.play(
            .item(MediaIdentity(server: ServerIdentity(provider: .jellyfin, id: "s2"), itemID: "abc"), kind: .movie),
            mode: .resume,
        )))
    }

    @Test func `catalog links read their ids and search hints`() {
        let parsed = link("strimr://play?type=movie&imdb=TT0111161&title=The%20Shawshank%20Redemption&year=1994")
        #expect(parsed == DeepLink(.play(
            .catalog(.init(
                kind: .movie,
                ids: ExternalIDs(imdb: "tt0111161"),
                title: "The Shawshank Redemption",
                year: 1994,
            )),
            mode: .resume,
        )))
    }

    @Test func `play options accept any form of a language code`() {
        let parsed = link("strimr://play/42?server=s1&offset=600&audio=FRE&subs=OFF")
        #expect(parsed == DeepLink(.play(
            .item(MediaIdentity(server: ServerIdentity(provider: .plex, id: "s1"), itemID: "42"), kind: nil),
            mode: .resume,
            options: PlaybackStartOptions(offset: 600, audioLanguage: "fr", subtitles: .off),
        )))
        #expect(link("strimr://play/42?server=s1&subs=eng") == link("strimr://play/42?server=s1&subs=en"))
    }

    @Test func `malformed links are refused`() {
        #expect(link("strimr://play/42?server=s1&offset=-5") == nil)
        #expect(link("strimr://play/42?server=s1&offset=soon") == nil)
        #expect(link("strimr://play/42?server=s1&audio=xx") == nil)
        #expect(link("strimr://play/42?server=s1&subs=und") == nil)
        #expect(link("strimr://play/42?server=s1&mode=loop") == nil)
        #expect(link("strimr://play?type=movie&imdb=0111161") == nil)
        #expect(link("strimr://play?type=movie&tmdb=abc") == nil)
        #expect(link("strimr://play?type=movie&tmdb=1&year=94") == nil)
        #expect(link("strimr://play?type=episode&tmdb=1") == nil)
        #expect(link("strimr://play?type=movie") == nil)
        #expect(link("strimr://media/42") == nil)
        #expect(link("strimr://media/42?provider=emby&server=s1") == nil)
        #expect(link("strimr://library?server=s1") == nil)
        #expect(link("strimr://live/TF1?provider=plex") == nil)
        #expect(link("strimr://tab/settings") == nil)
        #expect(link("strimr://unknown") == nil)
        #expect(link("https://media/42?server=s1") == nil)
    }

    @Test func `external player callbacks are not links`() {
        #expect(link("strimr://x-callback-url/playbackDidFinish?position=10") == nil)
    }

    @Test func `tab names ignore case`() {
        #expect(link("strimr://tab/LIVETV") == DeepLink(.tab(.liveTV)))
    }

    @Test func `share links use one catalog id`() {
        let movie = MediaItem.make(
            id: "1",
            server: plex,
            title: "Heat",
            externalIDs: ExternalIDs(imdb: "tt0113277", tmdb: "949", tvdb: "123"),
            year: 1995,
        )
        #expect(DeepLink.shareLink(for: movie, profile: "local.a") == DeepLink(
            .media(.catalog(.init(kind: .movie, ids: ExternalIDs(tmdb: "949"), title: "Heat", year: 1995))),
            profile: "local.a",
        ))

        let show = MediaItem.make(
            id: "2",
            server: plex,
            title: "Lost",
            type: .series,
            externalIDs: ExternalIDs(imdb: "tt0411008", tmdb: "4607", tvdb: "73739"),
        )
        #expect(DeepLink.catalogTarget(for: show)?.ids == ExternalIDs(tvdb: "73739"))

        let imdbOnly = MediaItem.make(id: "3", server: plex, externalIDs: ExternalIDs(imdb: "tt1"))
        #expect(DeepLink.catalogTarget(for: imdbOnly)?.ids == ExternalIDs(imdb: "tt1"))
    }

    @Test func `share links fall back to the server item`() {
        let unmatched = MediaItem.make(id: "1", server: jellyfin)
        #expect(DeepLink.shareLink(for: unmatched, profile: nil) == DeepLink(.media(.item(
            unmatched.identity,
            kind: .movie,
        ))))

        let episode = MediaItem.make(
            id: "2",
            server: plex,
            type: .episode,
            externalIDs: ExternalIDs(tvdb: "1"),
        )
        #expect(DeepLink.shareLink(for: episode, profile: nil) == DeepLink(.media(.item(
            episode.identity,
            kind: .episode,
        ))))

        #expect(DeepLink.shareLink(for: MediaItem.make(id: "3", server: plex, type: .playlist), profile: nil) == nil)
    }
}
