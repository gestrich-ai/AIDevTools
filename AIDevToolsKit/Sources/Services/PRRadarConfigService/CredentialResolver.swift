import EnvironmentSDK
import Foundation
import KeychainSDK

public struct CredentialResolver: Sendable {
    public static let githubTokenKey = "GITHUB_TOKEN"
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    public static let gitHubAppIdKey = "GITHUB_APP_ID"
    public static let gitHubAppInstallationIdKey = "GITHUB_APP_INSTALLATION_ID"
    public static let gitHubAppPrivateKeyKey = "GITHUB_APP_PRIVATE_KEY"

    private let processEnvironment: [String: String]
    private let dotEnv: [String: String]
    private let keychain: KeychainStoring
    private let githubProfileId: String?

    public init(
        keychain: KeychainStoring,
        githubProfileId: String?,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String]? = nil
    ) {
        self.keychain = keychain
        self.githubProfileId = githubProfileId
        self.processEnvironment = processEnvironment
        self.dotEnv = dotEnv ?? DotEnvironmentLoader().loadDotEnv()
    }

    public static func createPlatform(githubProfileId: String?) -> CredentialResolver {
        let keychain: KeychainStoring
        #if os(macOS)
        keychain = SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        #else
        keychain = EnvironmentKeychainStore()
        #endif
        return CredentialResolver(keychain: keychain, githubProfileId: githubProfileId)
    }

    public func getGitHubAuth() -> GitHubAuth? {
        if let auth = resolveGitHubAppAuthFromEnv() {
            return auth
        }
        if let profileId = githubProfileId {
            let namedTokenKey = "\(Self.githubTokenKey)_\(profileId)"
            if let token = processEnvironment[namedTokenKey] ?? dotEnv[namedTokenKey] {
                return .token(token)
            }
            if let token = try? keychain.string(forKey: "github-profiles/\(profileId)/token") {
                return .token(token)
            }
            if let appId = try? keychain.string(forKey: "github-profiles/\(profileId)/app-id"),
               let installationId = try? keychain.string(forKey: "github-profiles/\(profileId)/installation-id"),
               let privateKey = try? keychain.string(forKey: "github-profiles/\(profileId)/private-key") {
                return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
            }
        }
        if let token = processEnvironment[Self.githubTokenKey] ?? dotEnv[Self.githubTokenKey] {
            return .token(token)
        }
        return nil
    }

    public func getAnthropicKey() -> String? {
        if let v = processEnvironment[Self.anthropicAPIKeyKey] { return v }
        if let v = dotEnv[Self.anthropicAPIKeyKey] { return v }
        return nil
    }

    private func resolveGitHubAppAuthFromEnv() -> GitHubAuth? {
        if let profileId = githubProfileId {
            let namedAppIdKey = "\(Self.gitHubAppIdKey)_\(profileId)"
            let namedInstallationIdKey = "\(Self.gitHubAppInstallationIdKey)_\(profileId)"
            let namedPrivateKeyKey = "\(Self.gitHubAppPrivateKeyKey)_\(profileId)"
            if let appId = processEnvironment[namedAppIdKey] ?? dotEnv[namedAppIdKey],
               let installationId = processEnvironment[namedInstallationIdKey] ?? dotEnv[namedInstallationIdKey],
               let privateKey = processEnvironment[namedPrivateKeyKey] ?? dotEnv[namedPrivateKeyKey] {
                return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
            }
        }
        guard let appId = processEnvironment[Self.gitHubAppIdKey] ?? dotEnv[Self.gitHubAppIdKey],
              let installationId = processEnvironment[Self.gitHubAppInstallationIdKey] ?? dotEnv[Self.gitHubAppInstallationIdKey],
              let privateKey = processEnvironment[Self.gitHubAppPrivateKeyKey] ?? dotEnv[Self.gitHubAppPrivateKeyKey] else {
            return nil
        }
        return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
    }
}
