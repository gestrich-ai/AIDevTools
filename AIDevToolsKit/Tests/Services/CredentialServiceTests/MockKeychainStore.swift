import Foundation
import KeychainSDK

final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func setString(_ string: String, forKey key: String) throws {
        storage[key] = string
    }

    func string(forKey key: String) throws -> String {
        guard let value = storage[key] else {
            throw KeychainStoreError.itemNotFound
        }
        return value
    }

    func removeObject(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }

    func allKeys() throws -> Set<String> {
        Set(storage.keys)
    }
}
