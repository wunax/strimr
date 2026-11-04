import Foundation
@testable import Strimr
import Testing

struct JellyfinRemoteSubtitleTests {
    @Test func `forced subtitles are read from the Forced field`() throws {
        let data = Data(#"{"Id":"1","Forced":true}"#.utf8)

        let subtitle = try JSONDecoder().decode(JellyfinRemoteSubtitle.self, from: data)

        #expect(subtitle.isForced == true)
    }
}
