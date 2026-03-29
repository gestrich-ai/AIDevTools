import Foundation
import KeychainSDK

public final class CredentialSettingsService: Sendable {
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

    // MARK: - GitHub Auth (Keychain)

    public func saveGitHubAuth(_ auth: GitHubAuth, account: String) throws {
        switch auth {
        case .token(let token):
            try keychain.setString(token, forKey: credentialKey(account: account, type: Self.gitHubTokenType))
            try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubAppIdType))
            try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubAppInstallationIdType))
            try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubAppPrivateKeyType))
        case .app(let appId, let installationId, let privateKeyPEM):
            try keychain.setString(appId, forKey: credentialKey(account: account, type: Self.gitHubAppIdType))
            try keychain.setString(installationId, forKey: credentialKey(account: account, type: Self.gitHubAppInstallationIdType))
            try keychain.setString(privateKeyPEM, forKey: credentialKey(account: account, type: Self.gitHubAppPrivateKeyType))
            try? keychain.removeObject(forKey: credentialKey(account: account, type: Self.gitHubTokenType))
        }
    }

    public func loadGitHubAuth(account: String) -> GitHubAuth? {
        if let appId = try? loadCredential(account: account, type: Self.gitHubAppIdType),
           let installationId = try? loadCredential(account: account, type: Self.gitHubAppInstallationIdType),
           let privateKey = try? loadCredential(account: account, type: Self.gitHubAppPrivateKeyType) {
            return .app(appId: appId, installationId: installationId, privateKeyPEM: privateKey)
        }
        if let token = try? loadCredential(account: account, type: Self.gitHubTokenType) {
            return .token(token)
        }
        return nil
    }

    // MARK: - Anthropic Key (Keychain)

    public func saveAnthropicKey(_ apiKey: String, account: String) throws {
        try keychain.setString(apiKey, forKey: credentialKey(account: account, type: Self.anthropicKeyType))
    }

    public func loadAnthropicKey(account: String) throws -> String {
        try loadCredential(account: account, type: Self.anthropicKeyType)
    }

    // MARK: - Credential Management

    public func removeCredentials(account: String) throws {
        for type in [Self.anthropicKeyType, Self.gitHubAppIdType, Self.gitHubAppInstallationIdType, Self.gitHubAppPrivateKeyType, Self.gitHubTokenType] {
            try? keychain.removeObject(forKey: credentialKey(account: account, type: type))
        }
    }

    public func listCredentialAccounts() throws -> [String] {
        let keys = try keychain.allKeys()
        let accounts = Set(keys.compactMap { key -> String? in
            guard let slashIndex = key.firstIndex(of: "/") else { return nil }
            return String(key[key.startIndex..<slashIndex])
        })
        return accounts.sorted()
    }

    // MARK: - Internal

    func loadCredential(account: String, type: String) throws -> String {
        try keychain.string(forKey: credentialKey(account: account, type: type))
    }

    private func credentialKey(account: String, type: String) -> String {
        "\(account)/\(type)"
    }
}
