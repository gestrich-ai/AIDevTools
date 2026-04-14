import Testing
@testable import KeychainSDK

@Suite("EnvironmentKeychainStore")
struct EnvironmentKeychainStoreTests {

    @Test("resolves github-profiles token from GITHUB_TOKEN env var")
    func resolvesGitHubToken() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc123"])
        let value = try store.string(forKey: "github-profiles/myaccount/token")
        #expect(value == "ghp_abc123")
    }

    @Test("resolves anthropic-profiles api-key from ANTHROPIC_API_KEY env var")
    func resolvesAnthropicKey() throws {
        let store = EnvironmentKeychainStore(environment: ["ANTHROPIC_API_KEY": "sk-ant-test"])
        let value = try store.string(forKey: "anthropic-profiles/work/api-key")
        #expect(value == "sk-ant-test")
    }

    @Test("resolves github-profiles app-id from GITHUB_APP_ID env var")
    func resolvesGitHubAppId() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_ID": "12345"])
        let value = try store.string(forKey: "github-profiles/myaccount/app-id")
        #expect(value == "12345")
    }

    @Test("resolves github-profiles installation-id from GITHUB_APP_INSTALLATION_ID env var")
    func resolvesGitHubAppInstallationId() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_INSTALLATION_ID": "67890"])
        let value = try store.string(forKey: "github-profiles/myaccount/installation-id")
        #expect(value == "67890")
    }

    @Test("resolves github-profiles private-key from GITHUB_APP_PRIVATE_KEY env var")
    func resolvesGitHubAppPrivateKey() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_APP_PRIVATE_KEY": "-----BEGIN RSA"])
        let value = try store.string(forKey: "github-profiles/myaccount/private-key")
        #expect(value == "-----BEGIN RSA")
    }

    @Test("throws itemNotFound for missing env var")
    func throwsForMissingEnvVar() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "github-profiles/myaccount/token")
        }
    }

    @Test("throws itemNotFound for empty env var")
    func throwsForEmptyEnvVar() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": ""])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "github-profiles/myaccount/token")
        }
    }

    @Test("throws itemNotFound for unknown key type")
    func throwsForUnknownKeyType() {
        let store = EnvironmentKeychainStore(environment: ["SOME_VAR": "value"])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "github-profiles/myaccount/unknown-type")
        }
    }

    @Test("throws itemNotFound for key without enough components")
    func throwsForKeyWithoutEnoughComponents() {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc"])
        #expect(throws: KeychainStoreError.self) {
            try store.string(forKey: "github-token")
        }
    }

    @Test("setString throws readOnly")
    func setStringThrowsReadOnly() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.setString("value", forKey: "github-profiles/account/token")
        }
    }

    @Test("removeObject throws readOnly")
    func removeObjectThrowsReadOnly() {
        let store = EnvironmentKeychainStore(environment: [:])
        #expect(throws: KeychainStoreError.self) {
            try store.removeObject(forKey: "github-profiles/account/token")
        }
    }

    @Test("allKeys returns profile keys for set env vars")
    func allKeysReturnsSetEnvVars() throws {
        let store = EnvironmentKeychainStore(environment: [
            "GITHUB_TOKEN": "ghp_abc",
            "ANTHROPIC_API_KEY": "sk-ant-test",
        ])
        let keys = try store.allKeys()
        #expect(keys.contains("github-profiles/default/token"))
        #expect(keys.contains("anthropic-profiles/default/api-key"))
        #expect(!keys.contains("github-profiles/default/app-id"))
    }

    @Test("allKeys returns empty set when no env vars set")
    func allKeysReturnsEmptySetWhenNoEnvVars() throws {
        let store = EnvironmentKeychainStore(environment: [:])
        let keys = try store.allKeys()
        #expect(keys.isEmpty)
    }

    @Test("profile ID portion of key is ignored for resolution")
    func profileIdPortionIgnored() throws {
        let store = EnvironmentKeychainStore(environment: ["GITHUB_TOKEN": "ghp_abc"])
        let value1 = try store.string(forKey: "github-profiles/profile1/token")
        let value2 = try store.string(forKey: "github-profiles/profile2/token")
        #expect(value1 == value2)
    }
}
