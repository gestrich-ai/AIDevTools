import Foundation
import KeychainSDK
import Testing

@testable import CredentialService

struct CredentialSettingsServiceTests {
    @Test func saveAndLoadGitHubToken() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveGitHubAuth(.token("ghp_abc123"), account: "testaccount")
        let auth = service.loadGitHubAuth(account: "testaccount")

        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "ghp_abc123")
    }

    @Test func saveAndLoadGitHubApp() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveGitHubAuth(
            .app(appId: "123", installationId: "456", privateKeyPEM: "PEM_DATA"),
            account: "testaccount"
        )
        let auth = service.loadGitHubAuth(account: "testaccount")

        guard case .app(let appId, let installationId, let privateKey) = auth else {
            Issue.record("Expected .app, got \(String(describing: auth))")
            return
        }
        #expect(appId == "123")
        #expect(installationId == "456")
        #expect(privateKey == "PEM_DATA")
    }

    @Test func saveTokenClearsAppCredentials() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveGitHubAuth(
            .app(appId: "123", installationId: "456", privateKeyPEM: "PEM"),
            account: "testaccount"
        )
        try service.saveGitHubAuth(.token("ghp_new"), account: "testaccount")

        let auth = service.loadGitHubAuth(account: "testaccount")
        guard case .token(let token) = auth else {
            Issue.record("Expected .token after overwrite, got \(String(describing: auth))")
            return
        }
        #expect(token == "ghp_new")
    }

    @Test func saveAndLoadAnthropicKey() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveAnthropicKey("sk-ant-abc", account: "testaccount")
        let key = try service.loadAnthropicKey(account: "testaccount")
        #expect(key == "sk-ant-abc")
    }

    @Test func removeCredentialsClearsAll() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveGitHubAuth(.token("ghp_abc"), account: "testaccount")
        try service.saveAnthropicKey("sk-ant-abc", account: "testaccount")
        try service.removeCredentials(account: "testaccount")

        #expect(service.loadGitHubAuth(account: "testaccount") == nil)
        #expect(throws: KeychainStoreError.self) {
            try service.loadAnthropicKey(account: "testaccount")
        }
    }

    @Test func listCredentialAccounts() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        try service.saveGitHubAuth(.token("t1"), account: "alice")
        try service.saveAnthropicKey("k1", account: "bob")
        try service.saveGitHubAuth(.token("t2"), account: "alice")

        let accounts = try service.listCredentialAccounts()
        #expect(accounts == ["alice", "bob"])
    }

    @Test func loadGitHubAuthReturnsNilWhenEmpty() {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)
        #expect(service.loadGitHubAuth(account: "nonexistent") == nil)
    }
}
