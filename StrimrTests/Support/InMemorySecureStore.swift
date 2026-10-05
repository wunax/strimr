import Foundation
@testable import Strimr

final class InMemorySecureStore: SecureStore {
    struct Failure: Error {}

    var values: [String: String] = [:]
    var failsReads = false

    init(_ values: [String: String] = [:]) {
        self.values = values
    }

    func string(forKey key: String) throws -> String? {
        if failsReads {
            throw Failure()
        }
        return values[key]
    }

    func setString(_ value: String, forKey key: String) throws {
        values[key] = value
    }

    func deleteValue(forKey key: String) throws {
        values[key] = nil
    }
}

enum TestDefaults {
    /// A throwaway suite so tests never touch the app's settings.
    static func make() -> UserDefaults {
        let name = "strimr.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        defaults.removePersistentDomain(forName: name)
        return defaults
    }
}
