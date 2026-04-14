import Foundation
import KeychainSDK
import Testing

@Suite("EnvironmentKeychainStore")
struct EnvironmentKeychainStoreTests {

    // MARK: - Reading

    @Test("reads GitHub token from GITHUB_TOKEN env var")
    func readsGitHubToken() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc123"])

        let value = try store.string(forKey: "github-profiles/work/token")

        #expect(value == "ghp_abc123")
    }

    @Test("reads Anthropic key from ANTHROPIC_API_KEY env var")
    func readsAnthropicKey() throws {
        let store = EnvironmentKeychainStore(environment: ["ANTHROPIC_API_KEY": "sk-ant-xxx"])

        let value = try store.string(forKey: "anthropic-profiles/myaccount/api-key")

        #expect(value == "sk-ant-xxx")
    }

    @Test("profile ID portion of key is ignored")
    func profileIdIsIgnored() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_123"])

        let fromWork = try store.string(forKey: "github-profiles/work/token")
        let fromPersonal = try store.string(forKey: "github-profiles/personal/token")

        #expect(fromWork == fromPersonal)
    }

    @Test("throws itemNotFound when env var is missing")
    func throwsWhenMissing() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "github-profiles/work/token")
        }
    }

    @Test("throws itemNotFound when env var is empty string")
    func throwsWhenEmpty() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": ""])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "github-profiles/work/token")
        }
    }

    @Test("throws itemNotFound for unknown key type")
    func throwsForUnknownType() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_123"])

        #expect(throws: KeychainStoreError.self) {
            _ = try store.string(forKey: "github-profiles/work/unknown-type")
        }
    }

    // MARK: - Write operations

    @Test("setString throws readOnly")
    func setStringThrows() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            try store.setString("value", forKey: "github-profiles/work/token")
        }
    }

    @Test("removeObject throws readOnly")
    func removeObjectThrows() {
        let store = EnvironmentKeychainStore(environment: [:])

        #expect(throws: KeychainStoreError.self) {
            try store.removeObject(forKey: "github-profiles/work/token")
        }
    }

    // MARK: - allKeys

    @Test("allKeys returns profile keys for set env vars")
    func allKeysReturnsSetVars() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_123",
            "ANTHROPIC_API_KEY": "sk-ant-xxx",
        ])

        let keys = try store.allKeys()

        #expect(keys == Set(["github-profiles/default/token", "anthropic-profiles/default/api-key"]))
    }

    @Test("allKeys excludes empty env vars")
    func allKeysExcludesEmpty() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_123",
            "ANTHROPIC_API_KEY": "",
        ])

        let keys = try store.allKeys()

        #expect(keys == Set(["github-profiles/default/token"]))
    }

    @Test("allKeys returns empty when no env vars set")
    func allKeysEmpty() throws {
        let store = EnvironmentKeychainStore(environment: [:])

        let keys = try store.allKeys()

        #expect(keys.isEmpty)
    }
}
