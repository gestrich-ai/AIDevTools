import Foundation
import KeychainSDK
import Testing

@testable import CredentialService

@Suite("SecureSettingsService")
struct SecureSettingsServiceTests {
    @Test("saves and loads a GitHub token profile")
    func saveAndLoadGitHubToken() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(id: "testaccount", auth: .token("ghp_abc123")))
        let profile = service.loadGitHubProfile(id: "testaccount")

        guard case .token(let token) = profile?.auth else {
            Issue.record("Expected .token, got \(String(describing: profile?.auth))")
            return
        }
        #expect(token == "ghp_abc123")
    }

    @Test("saves and loads a GitHub App profile")
    func saveAndLoadGitHubApp() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(
            id: "testaccount",
            auth: .app(appId: "123", installationId: "456", privateKeyPEM: "PEM_DATA")
        ))
        let profile = service.loadGitHubProfile(id: "testaccount")

        guard case .app(let appId, let installationId, let privateKey) = profile?.auth else {
            Issue.record("Expected .app, got \(String(describing: profile?.auth))")
            return
        }
        #expect(appId == "123")
        #expect(installationId == "456")
        #expect(privateKey == "PEM_DATA")
    }

    @Test("saving a token profile clears existing app credentials")
    func saveTokenClearsAppCredentials() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(
            id: "testaccount",
            auth: .app(appId: "123", installationId: "456", privateKeyPEM: "PEM")
        ))
        try service.saveGitHubProfile(GitHubCredentialProfile(id: "testaccount", auth: .token("ghp_new")))

        let profile = service.loadGitHubProfile(id: "testaccount")
        guard case .token(let token) = profile?.auth else {
            Issue.record("Expected .token after overwrite, got \(String(describing: profile?.auth))")
            return
        }
        #expect(token == "ghp_new")
    }

    @Test("saving an app profile clears existing token credentials")
    func saveAppClearsTokenCredentials() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(id: "testaccount", auth: .token("ghp_old")))
        try service.saveGitHubProfile(GitHubCredentialProfile(
            id: "testaccount",
            auth: .app(appId: "111", installationId: "222", privateKeyPEM: "PEM")
        ))

        let profile = service.loadGitHubProfile(id: "testaccount")
        guard case .app(let appId, _, _) = profile?.auth else {
            Issue.record("Expected .app after overwrite, got \(String(describing: profile?.auth))")
            return
        }
        #expect(appId == "111")
    }

    @Test("saves and loads an Anthropic profile")
    func saveAndLoadAnthropicProfile() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveAnthropicProfile(AnthropicCredentialProfile(id: "testaccount", apiKey: "sk-ant-abc"))
        let profile = service.loadAnthropicProfile(id: "testaccount")
        #expect(profile?.apiKey == "sk-ant-abc")
    }

    @Test("removeGitHubProfile clears all keys for that profile")
    func removeGitHubProfileClearsAllKeys() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(id: "testaccount", auth: .token("ghp_abc")))
        service.removeGitHubProfile(id: "testaccount")

        #expect(service.loadGitHubProfile(id: "testaccount") == nil)
    }

    @Test("removeAnthropicProfile clears the api-key for that profile")
    func removeAnthropicProfileClearsKey() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveAnthropicProfile(AnthropicCredentialProfile(id: "testaccount", apiKey: "sk-ant-abc"))
        service.removeAnthropicProfile(id: "testaccount")

        #expect(service.loadAnthropicProfile(id: "testaccount") == nil)
    }

    @Test("listGitHubProfileIds enumerates saved GitHub profiles")
    func listGitHubProfileIds() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveGitHubProfile(GitHubCredentialProfile(id: "alice", auth: .token("t1")))
        try service.saveGitHubProfile(GitHubCredentialProfile(id: "alice", auth: .token("t2")))
        try service.saveAnthropicProfile(AnthropicCredentialProfile(id: "bob", apiKey: "k1"))

        let ids = try service.listGitHubProfileIds()
        #expect(ids == ["alice"])
    }

    @Test("listAnthropicProfileIds enumerates saved Anthropic profiles")
    func listAnthropicProfileIds() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        try service.saveAnthropicProfile(AnthropicCredentialProfile(id: "alice", apiKey: "k1"))
        try service.saveGitHubProfile(GitHubCredentialProfile(id: "bob", auth: .token("t1")))

        let ids = try service.listAnthropicProfileIds()
        #expect(ids == ["alice"])
    }

    @Test("loadGitHubProfile returns nil for a nonexistent profile")
    func loadGitHubProfileReturnsNilWhenEmpty() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)
        #expect(service.loadGitHubProfile(id: "nonexistent") == nil)
    }
}
