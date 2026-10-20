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
