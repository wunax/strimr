import Foundation
@testable import Strimr
import Testing

struct DownloadedMediaMetadataTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")

    @Test func `a download saved with a single subtitle keeps it as a subtitle file`() throws {
        var json = try encodedMetadata()
        json["subtitleFiles"] = nil
        json["subtitleTitle"] = "English"
        json["subtitleFileName"] = "subtitle.srt"
        json["subtitleLanguage"] = "en"
        json["subtitleCodec"] = "srt"
        json["subtitleIsForced"] = true

        let metadata = try decode(json)

        #expect(metadata.subtitleFiles == [DownloadedSubtitleFile(
            fileName: "subtitle.srt",
            title: "English",
            language: "en",
            codec: "srt",
            isForced: true,
            isHearingImpaired: false,
        )])
    }

    @Test func `a download saved without subtitle has no subtitle file`() throws {
        var json = try encodedMetadata()
        json["subtitleFiles"] = nil

        #expect(try decode(json).subtitleFiles.isEmpty)
    }

    @Test func `subtitle files survive encoding`() throws {
        var metadata = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server).metadata
        metadata.subtitleFiles = [
            DownloadedSubtitleFile(
                fileName: "subtitle-0.srt", title: "English", language: "en", codec: "srt",
                isForced: false, isHearingImpaired: true,
            ),
            DownloadedSubtitleFile(
                fileName: "subtitle-1.ass", title: nil, language: "fr", codec: "ass",
                isForced: true, isHearingImpaired: false,
            ),
        ]

        let decoded = try JSONDecoder().decode(
            DownloadedMediaMetadata.self,
            from: JSONEncoder().encode(metadata),
        )

        #expect(decoded.subtitleFiles == metadata.subtitleFiles)
    }

    private func encodedMetadata() throws -> [String: Any] {
        let metadata = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server).metadata
        let data = try JSONEncoder().encode(metadata)
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decode(_ json: [String: Any]) throws -> DownloadedMediaMetadata {
        try JSONDecoder().decode(
            DownloadedMediaMetadata.self,
            from: JSONSerialization.data(withJSONObject: json),
        )
    }
}
