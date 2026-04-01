import EnvironmentSDK
import Foundation

public struct CredentialResolver: Sendable {
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    public static let gitHubAppIdKey = "GITHUB_APP_ID"
    public static let gitHubAppInstallationIdKey = "GITHUB_APP_INSTALLATION_ID"
    public static let gitHubAppPrivateKeyKey = "GITHUB_APP_PRIVATE_KEY"
    public static let githubTokenKey = "GITHUB_TOKEN"

    private let account: String
    private let dotEnv: [String: String]
    private let processEnvironment: [String: String]
    private let settingsService: SecureSettingsService

    public init(
        settingsService: SecureSettingsService,
        githubAccount: String,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.settingsService = settingsService
        self.account = githubAccount
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? DotEnvironmentLoader.loadDotEnv()
    }

    public func getGitHubAuth() -> GitHubAuth? {
        if let auth = resolveGitHubAppAuth() {
            return auth
        }
        if let token = resolveValue(envKey: Self.githubTokenKey, keychainType: SecureSettingsService.gitHubTokenType) {
            return .token(token)
        }
        return nil
    }

    public func getAnthropicKey() -> String? {
        resolveValue(envKey: Self.anthropicAPIKeyKey, keychainType: SecureSettingsService.anthropicKeyType)
    }

    private func resolveGitHubAppAuth() -> GitHubAuth? {
        guard let appId = resolveValue(envKey: Self.gitHubAppIdKey, keychainType: SecureSettingsService.gitHubAppIdType),
              let installationId = resolveValue(envKey: Self.gitHubAppInstallationIdKey, keychainType: SecureSettingsService.gitHubAppInstallationIdType),
              let privateKey = resolveValue(envKey: Self.gitHubAppPrivateKeyKey, keychainType: SecureSettingsService.gitHubAppPrivateKeyType) else {
            return nil
        }
        return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
    }

    private func resolveValue(envKey: String, keychainType: String) -> String? {
        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? settingsService.loadCredential(account: account, type: keychainType)
    }
}
