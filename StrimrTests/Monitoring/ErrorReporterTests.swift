import Foundation
@testable import Strimr
import Testing

struct ErrorReporterTests {
    @Test func `a POSIX host unreachable error is recognized`() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EHOSTUNREACH))

        #expect(error.isHostUnreachable)
    }

    @Test func `other POSIX errors are not treated as host unreachable`() {
        let error = NSError(domain: NSPOSIXErrorDomain, code: Int(EADDRNOTAVAIL))

        #expect(!error.isHostUnreachable)
    }

    @Test func `the same code in another domain is not treated as host unreachable`() {
        let error = NSError(domain: NSURLErrorDomain, code: Int(EHOSTUNREACH))

        #expect(!error.isHostUnreachable)
    }
}

struct ErrorReporterBreadcrumbTests {
    @Test func `query and fragment are removed from network breadcrumbs`() {
        let data: [String: Any] = [
            "url": "https://media.example.com/library/metadata/1/thumb",
            "method": "GET",
            "http.query": "X-Plex-Token=secret",
            "http.fragment": "anchor",
        ]

        let sanitized = ErrorReporter.removingSensitiveData(from: data)

        #expect(sanitized?["http.query"] == nil)
        #expect(sanitized?["http.fragment"] == nil)
        #expect(sanitized?["url"] as? String == "https://media.example.com/library/metadata/1/thumb")
        #expect(sanitized?["method"] as? String == "GET")
    }

    @Test func `breadcrumbs without data stay without data`() {
        #expect(ErrorReporter.removingSensitiveData(from: nil) == nil)
    }
}
