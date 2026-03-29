import Foundation
import KeychainSDK
import Testing

@testable import CredentialService

struct CredentialResolverTests {
    @Test func envVarWinsOverKeychain() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: ["ANTHROPIC_API_KEY": "env-key"],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == "env-key")
    }

    @Test func dotEnvWinsOverKeychain() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: ["ANTHROPIC_API_KEY": "dotenv-key"]
        )

        #expect(resolver.getAnthropicKey() == "dotenv-key")
    }

    @Test func keychainUsedWhenEnvMissing() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)
        try service.saveAnthropicKey("keychain-key", account: "testaccount")

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == "keychain-key")
    }

    @Test func returnsNilWhenNoSourceHasValue() {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

        let resolver = CredentialResolver(
            settingsService: service,
            githubAccount: "testaccount",
            processEnvironment: [:],
            dotEnv: [:]
        )

        #expect(resolver.getAnthropicKey() == nil)
        #expect(resolver.getGitHubAuth() == nil)
    }

    @Test func gitHubTokenResolution() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

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

    @Test func gitHubAppAuthFromEnv() {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

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

    @Test func appAuthTakesPriorityOverToken() throws {
        let keychain = MockKeychainStore()
        let service = CredentialSettingsService(keychain: keychain)

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
}
