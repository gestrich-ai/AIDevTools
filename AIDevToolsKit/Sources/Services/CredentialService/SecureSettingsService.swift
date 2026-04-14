import Foundation
import KeychainSDK

public final class SecureSettingsService: Sendable {
    public static let anthropicKeyType = "anthropic-api-key"
    public static let gitHubAppIdType = "github-app-id"
    public static let gitHubAppInstallationIdType = "github-app-installation-id"
    public static let gitHubAppPrivateKeyType = "github-app-private-key"
    public static let gitHubTokenType = "github-token"

    private let keychain: KeychainStoring

    public init() {
        self.keychain = Self.platformKeychain()
    }

    public init(keychain: KeychainStoring) {
        self.keychain = keychain
    }

    private static func platformKeychain() -> KeychainStoring {
        #if os(macOS)
        SecurityCLIKeychainStore(identifier: "com.gestrich.AIDevTools")
        #else
        EnvironmentKeychainStore()
        #endif
    }

    // MARK: - GitHub Profiles

    public func saveGitHubProfile(_ profile: GitHubCredentialProfile) throws {
        let id = profile.id
        switch profile.auth {
        case .token(let token):
            try keychain.setString(token, forKey: githubProfileKey(id, "token"))
            try? keychain.removeObject(forKey: githubProfileKey(id, "app-id"))
            try? keychain.removeObject(forKey: githubProfileKey(id, "installation-id"))
            try? keychain.removeObject(forKey: githubProfileKey(id, "private-key"))
        case .app(let appId, let installationId, let privateKeyPEM):
            try keychain.setString(appId, forKey: githubProfileKey(id, "app-id"))
            try keychain.setString(installationId, forKey: githubProfileKey(id, "installation-id"))
            try keychain.setString(privateKeyPEM, forKey: githubProfileKey(id, "private-key"))
            try? keychain.removeObject(forKey: githubProfileKey(id, "token"))
        }
    }

    public func loadGitHubProfile(id: String) -> GitHubCredentialProfile? {
        if let appId = try? keychain.string(forKey: githubProfileKey(id, "app-id")),
           let installationId = try? keychain.string(forKey: githubProfileKey(id, "installation-id")),
           let privateKey = try? keychain.string(forKey: githubProfileKey(id, "private-key")) {
            return GitHubCredentialProfile(id: id, auth: .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey))
        }
        if let token = try? keychain.string(forKey: githubProfileKey(id, "token")) {
            return GitHubCredentialProfile(id: id, auth: .token(token))
        }
        return nil
    }

    public func removeGitHubProfile(id: String) {
        for suffix in ["app-id", "installation-id", "private-key", "token"] {
            try? keychain.removeObject(forKey: githubProfileKey(id, suffix))
        }
    }

    public func listGitHubProfileIds() throws -> [String] {
        let keys = try keychain.allKeys()
        let prefix = "github-profiles/"
        let profileIds = Set(keys.compactMap { key -> String? in
            guard key.hasPrefix(prefix) else { return nil }
            let remainder = String(key.dropFirst(prefix.count))
            guard let slashIndex = remainder.firstIndex(of: "/") else { return nil }
            return String(remainder[remainder.startIndex..<slashIndex])
        })
        return profileIds.sorted()
    }

    // MARK: - Anthropic Profiles

    public func saveAnthropicProfile(_ profile: AnthropicCredentialProfile) throws {
        try keychain.setString(profile.apiKey, forKey: anthropicProfileKey(profile.id))
    }

    public func loadAnthropicProfile(id: String) -> AnthropicCredentialProfile? {
        guard let apiKey = try? keychain.string(forKey: anthropicProfileKey(id)) else { return nil }
        return AnthropicCredentialProfile(id: id, apiKey: apiKey)
    }

    public func removeAnthropicProfile(id: String) {
        try? keychain.removeObject(forKey: anthropicProfileKey(id))
    }

    public func listAnthropicProfileIds() throws -> [String] {
        let keys = try keychain.allKeys()
        let prefix = "anthropic-profiles/"
        let profileIds = Set(keys.compactMap { key -> String? in
            guard key.hasPrefix(prefix) else { return nil }
            let remainder = String(key.dropFirst(prefix.count))
            guard let slashIndex = remainder.firstIndex(of: "/") else { return nil }
            return String(remainder[remainder.startIndex..<slashIndex])
        })
        return profileIds.sorted()
    }

    // MARK: - Internal

    // Bridge used by CredentialResolver (Phase 3 will remove this).
    // Maps old account+type pairs to the new profile key format.
    func loadCredential(account: String, type: String) throws -> String {
        try keychain.string(forKey: profileKey(account: account, type: type))
    }

    // MARK: - Key Helpers

    private func githubProfileKey(_ profileId: String, _ suffix: String) -> String {
        "github-profiles/\(profileId)/\(suffix)"
    }

    private func anthropicProfileKey(_ profileId: String) -> String {
        "anthropic-profiles/\(profileId)/api-key"
    }

    private func profileKey(account: String, type: String) -> String {
        switch type {
        case Self.anthropicKeyType:
            return anthropicProfileKey(account)
        case Self.gitHubTokenType:
            return githubProfileKey(account, "token")
        case Self.gitHubAppIdType:
            return githubProfileKey(account, "app-id")
        case Self.gitHubAppInstallationIdType:
            return githubProfileKey(account, "installation-id")
        case Self.gitHubAppPrivateKeyType:
            return githubProfileKey(account, "private-key")
        default:
            return "\(account)/\(type)"
        }
    }
}
