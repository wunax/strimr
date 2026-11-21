import Foundation
@testable import Strimr
import Testing

struct DownloadModelsTests {
    private let server = ServerIdentity(provider: .plex, id: "server-1")
    private let url = URL(string: "https://media.example.com/video")!

    @Test func `a failed download can be retried`() {
        let failed = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server, status: .failed)

        #expect(failed.canRetry(among: [failed]))
    }

    @Test(arguments: [DownloadStatus.queued, .preparing, .downloading, .completed])
    func `only a failed download can be retried`(status: DownloadStatus) {
        let item = DownloadItem.make(id: "download-1", itemID: "movie-1", server: server, status: status)

        #expect(!item.canRetry(among: [item]))
    }

    @Test func `a failed download cannot be retried once the same media was downloaded again`() {
        let failed = DownloadItem.make(
            id: "download-1", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let again = DownloadItem.make(
            id: "download-2", itemID: "movie-1", server: server, status: .downloading, ownerID: "user-1",
        )

        #expect(!failed.canRetry(among: [failed, again]))
    }

    @Test func `other failed copies or other users' downloads do not block a retry`() {
        let failed = DownloadItem.make(
            id: "download-1", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let otherFailed = DownloadItem.make(
            id: "download-2", itemID: "movie-1", server: server, status: .failed, ownerID: "user-1",
        )
        let otherUser = DownloadItem.make(
            id: "download-3", itemID: "movie-1", server: server, status: .completed, ownerID: "user-2",
        )

        #expect(failed.canRetry(among: [failed, otherFailed, otherUser]))
    }

    @Test(arguments: [401, 404, 500, 503])
    func `an error response is not kept as a video`(statusCode: Int) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)

        #expect(DownloadedFileValidation.failureMessage(response: response, fileSize: 512) != nil)
    }

    @Test func `an empty file is not kept as a video`() {
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil)

        #expect(DownloadedFileValidation.failureMessage(response: response, fileSize: 0) != nil)
    }

    @Test(arguments: [200, 206])
    func `a successful response with content is kept`(statusCode: Int) {
        let response = HTTPURLResponse(url: url, statusCode: statusCode, httpVersion: nil, headerFields: nil)

        #expect(DownloadedFileValidation.failureMessage(response: response, fileSize: 512) == nil)
    }
}
