import EnvironmentSDK
import Foundation
import KeychainSDK

public struct CredentialResolver: Sendable {
    public static let githubTokenKey = "GITHUB_TOKEN"
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    public static let gitHubAppIdKey = "GITHUB_APP_ID"
    public static let gitHubAppInstallationIdKey = "GITHUB_APP_INSTALLATION_ID"
    public static let gitHubAppPrivateKeyKey = "GITHUB_APP_PRIVATE_KEY"

    static let gitHubTokenType = "github-token"
    static let anthropicKeyType = "anthropic-api-key"
    static let gitHubAppIdType = "github-app-id"
    static let gitHubAppInstallationIdType = "github-app-installation-id"
    static let gitHubAppPrivateKeyType = "github-app-private-key"

    private let processEnvironment: [String: String]
    private let dotEnv: [String: String]
    private let keychain: KeychainStoring
    private let account: String

    public init(
        keychain: KeychainStoring,
        githubAccount: String,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.keychain = keychain
        self.account = githubAccount
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? DotEnvironmentLoader.loadDotEnv()
    }

    public static func createPlatform(githubAccount: String) -> CredentialResolver {
        let keychain: KeychainStoring
        #if os(macOS)
        keychain = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        #else
        keychain = EnvironmentKeychainStore()
        #endif
        return CredentialResolver(keychain: keychain, githubAccount: githubAccount)
    }

    public func getGitHubAuth() -> GitHubAuth? {
        if let auth = resolveGitHubAppAuth() {
            return auth
        }
        if let token = resolveValue(envKey: Self.githubTokenKey, keychainType: Self.gitHubTokenType) {
            return .token(token)
        }
        return nil
    }

    public func getAnthropicKey() -> String? {
        resolveValue(envKey: Self.anthropicAPIKeyKey, keychainType: Self.anthropicKeyType)
    }

    private func resolveGitHubAppAuth() -> GitHubAuth? {
        guard let appId = resolveValue(envKey: Self.gitHubAppIdKey, keychainType: Self.gitHubAppIdType),
              let installationId = resolveValue(envKey: Self.gitHubAppInstallationIdKey, keychainType: Self.gitHubAppInstallationIdType),
              let privateKey = resolveValue(envKey: Self.gitHubAppPrivateKeyKey, keychainType: Self.gitHubAppPrivateKeyType) else {
            return nil
        }
        return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
    }

    private func resolveValue(envKey: String, keychainType: String) -> String? {
        if let v = processEnvironment[envKey] { return v }
        if let v = dotEnv[envKey] { return v }
        return try? keychain.string(forKey: credentialKey(type: keychainType))
    }

    private func credentialKey(type: String) -> String {
        "\(account)/\(type)"
    }
}
