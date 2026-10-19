import Foundation
@testable import Strimr
import Testing

struct PlexMarkerTests {
    private func decodeMarkers(_ types: [String]) throws -> [PlexMarker] {
        let markers = types.enumerated().map { index, type in
            #"{"id": \#(index), "type": "\#(type)", "startTimeOffset": 0, "endTimeOffset": 1000}"#
        }
        let json = #"[\#(markers.joined(separator: ","))]"#
        return try JSONDecoder().decode([PlexMarker].self, from: Data(json.utf8))
    }

    @Test func `decodes DVR commercial markers`() throws {
        let markers = try decodeMarkers(["intro", "commercial", "credits"])

        #expect(markers.map(\.type) == [.intro, .commercial, .credits])
    }

    @Test func `falls back to unknown for unrecognized marker types`() throws {
        let markers = try decodeMarkers(["advertisement"])

        #expect(markers.map(\.type) == [.unknown])
        #expect(markers.first?.isIntro == false)
        #expect(markers.first?.isCredits == false)
    }

    @Test func `maps commercial markers to skip segments and drops unknown ones`() throws {
        let markers = try decodeMarkers(["intro", "commercial", "credits", "advertisement"])

        #expect(markers.compactMap(\.skipSegment).map(\.kind) == [.intro, .commercial, .credits])
    }
}
