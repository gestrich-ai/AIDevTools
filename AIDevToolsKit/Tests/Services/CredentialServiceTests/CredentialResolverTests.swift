import Foundation
import KeychainSDK
import Testing

@testable import CredentialService

struct CredentialResolverTests {
    @Test("env var wins over keychain for Anthropic key")
    func envVarWinsOverKeychain() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: ["ANTHROPIC_API_KEY": "env-key"],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == "env-key")
    }

    @Test("dotEnv wins over keychain for Anthropic key")
    func dotEnvWinsOverKeychain() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: ["ANTHROPIC_API_KEY": "dotenv-key"]
        )

        #expect(resolver.getAnthropicKey() == "dotenv-key")
    }

    @Test("keychain is used when env key is missing")
    func keychainUsedWhenEnvMissing() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == "keychain-key")
    }

    @Test("returns nil when no credential source has a value")
    func returnsNilWhenNoSourceHasValue() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == nil)
        #expect(resolver.getGitHubAuth() == nil)
    }

    @Test("resolves GitHub token from process environment")
    func gitHubTokenResolution() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: ["GITHUB_TOKEN": "ghp_envtoken"],
            dotEnv: [:]
        )

        let auth = resolver.getGitHubAuth()
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "ghp_envtoken")
    }

    @Test("resolves GitHub App auth from process environment")
    func gitHubAppAuthFromEnv() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [
                "GITHUB_APP_ID": "111",
                "GITHUB_APP_INSTALLATION_ID": "222",
                "GITHUB_APP_PRIVATE_KEY": "PEM",
            ],
            dotEnv: [:]
        )

        let auth = resolver.getGitHubAuth()
        guard case .app(let appId, let installationId, let privateKey) = auth else {
            Issue.record("Expected .app, got \(String(describing: auth))")
            return
        }
        #expect(appId == "111")
        #expect(installationId == "222")
        #expect(privateKey == "PEM")
    }

    @Test("GitHub App auth takes priority over token")
    func appAuthTakesPriorityOverToken() throws {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [
                "GITHUB_APP_ID": "111",
                "GITHUB_APP_INSTALLATION_ID": "222",
                "GITHUB_APP_PRIVATE_KEY": "PEM",
                "GITHUB_TOKEN": "ghp_shouldnotbeused",
            ],
            dotEnv: [:]
        )

        let auth = resolver.getGitHubAuth()
        guard case .app = auth else {
            Issue.record("Expected .app to take priority, got \(String(describing: auth))")
            return
        }
    }

    @Test("named env key GITHUB_TOKEN_<account> takes priority over unnamed GITHUB_TOKEN")
    func namedEnvKeyTakesPriorityOverUnnamed() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "gestrich",
            processEnvironment: [:],
            dotEnv: [
                "GITHUB_TOKEN_gestrich": "named-token",
                "GITHUB_TOKEN": "unnamed-token",
            ]
        )

        let auth = resolver.getGitHubAuth()
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "named-token")
    }

    @Test("unnamed GITHUB_TOKEN is used as fallback when no named key exists")
    func unnamedTokenUsedAsFallback() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "gestrich",
            processEnvironment: [:],
            dotEnv: ["GITHUB_TOKEN": "fallback-token"]
        )

        let auth = resolver.getGitHubAuth()
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "fallback-token")
    }

    @Test("withExplicitToken returns given token regardless of env and keychain")
    func explicitTokenIgnoresOtherSources() {
        let resolver = CredentialResolver.withExplicitToken("explicit-token")

        let auth = resolver.getGitHubAuth()
        guard case .token(let token) = auth else {
            Issue.record("Expected .token, got \(String(describing: auth))")
            return
        }
        #expect(token == "explicit-token")
    }

    @Test("requireGitHubAuth throws notConfigured when no credentials exist")
    func requireGitHubAuthThrowsWhenNoCredentials() {
        let keychain = MockKeychainStore()
        let service = SecureSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "gestrich",
            processEnvironment: [:],
            dotEnv: [:]
        )

        #expect(throws: CredentialError.self) {
            try resolver.requireGitHubAuth()
        }
    }
}
