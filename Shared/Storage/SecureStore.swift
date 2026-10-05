import Foundation

/// Storage for secrets, backed by the Keychain in the app.
protocol SecureStore {
    func string(forKey key: String) throws -> String?
    func setString(_ value: String, forKey key: String) throws
    func deleteValue(forKey key: String) throws
}

extension Keychain: SecureStore {}
