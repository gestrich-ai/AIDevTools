import Foundation

/// Maps keychain key types to environment variable names.
/// Keys follow the format "prefix/profileId/suffix" (e.g., "github-profiles/work/token").
/// The profile ID portion is ignored — env vars are not profile-scoped.
public struct EnvironmentKeychainStore: KeychainStoring {
    private let environment: [String: String]

    public init(environment: [String: String] = ProcessInfo.processInfo.environment) {
        self.environment = environment
    }

    public func setString(_ string: String, forKey key: String) throws {
        throw KeychainStoreError.readOnly
    }

    public func string(forKey key: String) throws -> String {
        guard let envVar = Self.envVarName(forKey: key),
              let value = environment[envVar], !value.isEmpty else {
            throw KeychainStoreError.itemNotFound
        }
        return value
    }

    public func removeObject(forKey key: String) throws {
        throw KeychainStoreError.readOnly
    }

    public func allKeys() throws -> Set<String> {
        var keys = Set<String>()
        let envVarToKey: [String: String] = [
            "ANTHROPIC_API_KEY": "anthropic-profiles/default/api-key",
            "GITHUB_APP_ID": "github-profiles/default/app-id",
            "GITHUB_APP_INSTALLATION_ID": "github-profiles/default/installation-id",
            "GITHUB_APP_PRIVATE_KEY": "github-profiles/default/private-key",
            "GITHUB_TOKEN": "github-profiles/default/token",
        ]
        for (envVar, key) in envVarToKey {
            if let value = environment[envVar], !value.isEmpty {
                keys.insert(key)
            }
        }
        return keys
    }

    static func envVarName(forKey key: String) -> String? {
        let components = key.split(separator: "/", maxSplits: 2)
        guard components.count == 3 else { return nil }
        let prefix = String(components[0])
        let suffix = String(components[2])
        switch (prefix, suffix) {
        case ("anthropic-profiles", "api-key"): return "ANTHROPIC_API_KEY"
        case ("github-profiles", "app-id"): return "GITHUB_APP_ID"
        case ("github-profiles", "installation-id"): return "GITHUB_APP_INSTALLATION_ID"
        case ("github-profiles", "private-key"): return "GITHUB_APP_PRIVATE_KEY"
        case ("github-profiles", "token"): return "GITHUB_TOKEN"
        default: return nil
        }
    }
}
