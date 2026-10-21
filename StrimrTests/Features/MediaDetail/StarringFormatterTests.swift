import Foundation
@testable import Strimr
import Testing

struct StarringFormatterTests {
    @Test func `keeps the first three distinct names`() {
        let cast = ["Ann", "Bob", "Ann", " ", "Cid", "Dee"].enumerated().map { index, name in
            CastMember(id: "\(index)", personID: nil, name: name, character: nil, thumbPath: nil)
        }

        #expect(StarringFormatter.text(from: cast) == String(localized: "media.detail.starring \("Ann, Bob, Cid")"))
    }

    @Test func `no cast means no line`() {
        #expect(StarringFormatter.text(from: []) == nil)
    }
}
