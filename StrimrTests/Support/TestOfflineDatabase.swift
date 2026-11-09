import Foundation
@testable import Strimr

/// An `OfflineDatabase` in its own temporary folder, removed when the value goes away.
final class TestOfflineDatabase {
    let database: OfflineDatabase
    let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("strimr.tests.\(UUID().uuidString)", isDirectory: true)
        database = try OfflineDatabase(
            applicationSupport: directory.appendingPathComponent("ApplicationSupport", isDirectory: true),
            caches: directory.appendingPathComponent("Caches", isDirectory: true),
        )
    }

    deinit {
        try? FileManager.default.removeItem(at: directory)
    }

    func makeStore() -> OfflineStore {
        OfflineStore(database: database)
    }
}
