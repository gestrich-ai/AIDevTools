import EnvironmentSDK
import Foundation

public struct CredentialResolver: Sendable {
    public static let anthropicAPIKeyKey = "ANTHROPIC_API_KEY"
    public static let gitHubAppIdKey = "GITHUB_APP_ID"
    public static let gitHubAppInstallationIdKey = "GITHUB_APP_INSTALLATION_ID"
    public static let gitHubAppPrivateKeyKey = "GITHUB_APP_PRIVATE_KEY"
    public static let githubTokenKey = "GITHUB_TOKEN"

    private let anthropicProfileId: String?
    private let dotEnv: [String: String]
    private let explicitToken: String?
    private let githubProfileId: String?
    private let processEnvironment: [String: String]
    private let settingsService: SecureSettingsService?

    public init(
        secureSettings: SecureSettingsService,
        githubProfileId: String?,
        anthropicProfileId: String?,
        processEnvironment: [String: String] = ProcessInfo.processInfo.environment,
        dotEnv: [String: String] = [:]
    ) {
        self.anthropicProfileId = anthropicProfileId
        self.dotEnv = dotEnv
        self.explicitToken = nil
        self.githubProfileId = githubProfileId
        self.processEnvironment = processEnvironment
        self.settingsService = secureSettings
    }

    private init(explicitToken: String) {
        self.anthropicProfileId = nil
        self.dotEnv = [:]
        self.explicitToken = explicitToken
        self.githubProfileId = nil
        self.processEnvironment = [:]
        self.settingsService = nil
    }

    public static func withExplicitToken(_ token: String) -> CredentialResolver {
        CredentialResolver(explicitToken: token)
    }

    public func getGitHubAuth() -> GitHubAuth? {
        if let token = explicitToken {
            return .token(token)
        }
        if let auth = resolveGitHubAppAuthFromEnv() {
            return auth
        }
        if let profileId = githubProfileId {
            let namedTokenKey = "\(Self.githubTokenKey)_\(profileId)"
            if let token = processEnvironment[namedTokenKey] ?? dotEnv[namedTokenKey] {
                return .token(token)
            }
        }
        if let profileId = githubProfileId,
           let service = settingsService,
           let profile = service.loadGitHubProfile(id: profileId) {
            return profile.auth
        }
        if let token = processEnvironment[Self.githubTokenKey] ?? dotEnv[Self.githubTokenKey] {
            return .token(token)
        }
        if let token = processEnvironment["GH_TOKEN"] ?? dotEnv["GH_TOKEN"] {
            return .token(token)
        }
        return nil
    }

    public func requireGitHubAuth() throws -> GitHubAuth {
        guard let auth = getGitHubAuth() else {
            throw CredentialError.notConfigured(profileId: githubProfileId)
        }
        return auth
    }

    /// Environment dict to pass to child processes (e.g. GitClient) so they inherit the GitHub token.
    public var gitEnvironment: [String: String]? {
        guard case .token(let token) = getGitHubAuth() else { return nil }
        return ["GH_TOKEN": token]
    }

    public func getAnthropicKey() -> String? {
        if let v = processEnvironment[Self.anthropicAPIKeyKey] { return v }
        if let v = dotEnv[Self.anthropicAPIKeyKey] { return v }
        if let profileId = anthropicProfileId,
           let service = settingsService,
           let profile = service.loadAnthropicProfile(id: profileId) {
            return profile.apiKey
        }
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
        if let appId = processEnvironment[Self.gitHubAppIdKey] ?? dotEnv[Self.gitHubAppIdKey],
           let installationId = processEnvironment[Self.gitHubAppInstallationIdKey] ?? dotEnv[Self.gitHubAppInstallationIdKey],
           let privateKey = processEnvironment[Self.gitHubAppPrivateKeyKey] ?? dotEnv[Self.gitHubAppPrivateKeyKey] {
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
        }
        return nil
    }
}
