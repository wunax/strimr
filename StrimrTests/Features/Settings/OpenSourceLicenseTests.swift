import Foundation
@testable import Strimr
import Testing

struct OpenSourceLicenseTests {
    @Test(arguments: [OpenSourceLicense.strimr] + OpenSourceLicense.dependencies)
    func `every license text is bundled`(license: OpenSourceLicense) {
        for file in license.textFiles {
            #expect(Bundle.main.url(forResource: "License-\(file)", withExtension: "txt") != nil, "\(file)")
        }
        #expect(!license.text.isEmpty)
    }

    @Test func `dependency names are unique`() {
        let names = OpenSourceLicense.dependencies.map(\.name)

        #expect(Set(names).count == names.count)
    }
}
