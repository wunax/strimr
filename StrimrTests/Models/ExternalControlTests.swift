import Foundation
@testable import Strimr
import Testing

struct ExternalControlTests {
    private func command(_ link: String) throws -> ExternalControlCommand? {
        try ExternalControlCommand(url: #require(URL(string: link)))
    }

    private func options(_ link: String) throws -> ExternalPlayOptions {
        try ExternalPlayOptions(query: #require(URL(string: link)).queryValues)
    }

    @Test func `parses the actions without parameters`() throws {
        #expect(try command("strimr://control/pause") == .pause)
        #expect(try command("strimr://control/resume") == .resume)
        #expect(try command("strimr://control/toggle") == .toggle)
        #expect(try command("strimr://control/skipIntro") == .skipIntro)
        #expect(try command("strimr://control/skipCredits") == .skipCredits)
        #expect(try command("strimr://control/next") == .next)
    }

    @Test func `parses an absolute and a relative seek`() throws {
        #expect(try command("strimr://control/seek?to=90.5") == .seekTo(90.5))
        #expect(try command("strimr://control/seek?by=30") == .seekBy(30))
        #expect(try command("strimr://control/seek?by=+30") == .seekBy(30))
        #expect(try command("strimr://control/seek?by=-15") == .seekBy(-15))
    }

    @Test func `an absolute seek wins over a relative one`() throws {
        #expect(try command("strimr://control/seek?by=10&to=60") == .seekTo(60))
    }

    @Test func `a negative absolute seek falls back to the relative one`() throws {
        #expect(try command("strimr://control/seek?to=-5&by=10") == .seekBy(10))
        #expect(try command("strimr://control/seek?to=-5") == nil)
    }

    @Test func `rejects a seek without a usable time`() throws {
        #expect(try command("strimr://control/seek") == nil)
        #expect(try command("strimr://control/seek?to=abc") == nil)
        #expect(try command("strimr://control/seek?to=nan") == nil)
        #expect(try command("strimr://control/seek?by=inf") == nil)
    }

    @Test func `ignores unknown actions and other links`() throws {
        #expect(try command("strimr://control/explode") == nil)
        #expect(try command("strimr://control") == nil)
        #expect(try command("strimr://play/1?type=movie") == nil)
        #expect(try command("other://control/pause") == nil)
    }

    @Test func `play options default to resuming from the saved position`() throws {
        let options = try options("strimr://play/1?type=movie")

        #expect(options.resume)
        #expect(options.offset == nil)
    }

    @Test func `reads resume and offset`() throws {
        #expect(try !options("strimr://play/1?resume=0").resume)
        #expect(try !options("strimr://play/1?resume=false").resume)
        #expect(try options("strimr://play/1?resume=1").resume)
        #expect(try options("strimr://play/1?resume=maybe").resume)
        #expect(try options("strimr://play/1?offset=600").offset == 600)
    }

    @Test func `ignores a negative or malformed offset`() throws {
        #expect(try options("strimr://play/1?offset=-3").offset == nil)
        #expect(try options("strimr://play/1?offset=soon").offset == nil)
        #expect(try options("strimr://play/1?offset=inf").offset == nil)
    }

    @Test func `parses track commands`() throws {
        #expect(try command("strimr://control/audio?lang=fr") == .audio(language: "fr"))
        #expect(try command("strimr://control/audio?lang=ENG") == .audio(language: "eng"))
        #expect(try command("strimr://control/subs?lang=es") == .subs(.language("es")))
        #expect(try command("strimr://control/subs?lang=off") == .subs(.off))
        #expect(try command("strimr://control/audio") == nil)
        #expect(try command("strimr://control/audio?lang=") == nil)
        #expect(try command("strimr://control/subs") == nil)
    }

    @Test func `reads the tracks of a play link`() throws {
        let link = try options("strimr://play/1?audio=ja&subs=en")

        #expect(link.audio == "ja")
        #expect(link.subs == .language("en"))
        #expect(try options("strimr://play/1?subs=off").subs == .off)
        #expect(try options("strimr://play/1?audio=&subs=").audio == nil)
        #expect(try options("strimr://play/1?audio=&subs=").subs == nil)
        #expect(try options("strimr://play/1").subs == nil)
    }

    @Test func `reads shuffle, off unless asked for`() throws {
        #expect(try options("strimr://play/9?type=collection&shuffle=1").shuffle)
        #expect(try options("strimr://play/9?type=collection&shuffle=true").shuffle)
        #expect(try !options("strimr://play/9?type=collection&shuffle=0").shuffle)
        #expect(try !options("strimr://play/9?type=collection").shuffle)
    }
}
