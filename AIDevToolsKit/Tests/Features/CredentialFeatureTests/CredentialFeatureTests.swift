import CredentialFeature
import CredentialService
import KeychainSDK
import Testing

private final class MockKeychainStore: KeychainStoring, @unchecked Sendable {
    private var storage: [String: String] = [:]

    func setString(_ string: String, forKey key: String) throws {
        storage[key] = string
    }

    func string(forKey key: String) throws -> String {
        guard let value = storage[key] else {
            throw KeychainStoreError.itemNotFound
        }
        return value
    }

    func removeObject(forKey key: String) throws {
        storage.removeValue(forKey: key)
    }

    func allKeys() throws -> Set<String> {
        Set(storage.keys)
    }
}

@Suite("SaveGitHubProfileUseCase")
struct SaveGitHubProfileUseCaseTests {
    @Test func savesTokenProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveGitHubProfileUseCase(settingsService: service)

        try useCase.execute(profile: GitHubCredentialProfile(id: "work", auth: .token("gh-token-123")))

        let loaded = service.loadGitHubProfile(id: "work")
        guard case .token(let token) = loaded?.auth else {
            Issue.record("Expected token auth")
            return
        }
        #expect(token == "gh-token-123")
    }

    @Test func savesAppProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveGitHubProfileUseCase(settingsService: service)

        try useCase.execute(profile: GitHubCredentialProfile(id: "work", auth: .app(appId: "123", installationId: "456", privateKeyPEM: "pem")))

        let loaded = service.loadGitHubProfile(id: "work")
        guard case .app(let appId, let installationId, let pem) = loaded?.auth else {
            Issue.record("Expected app auth")
            return
        }
        #expect(appId == "123")
        #expect(installationId == "456")
        #expect(pem == "pem")
    }
}

@Suite("ListGitHubProfilesUseCase")
struct ListGitHubProfilesUseCaseTests {
    @Test func listsProfilesAlphabetically() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveGitHubProfileUseCase(settingsService: service)
        let listUseCase = ListGitHubProfilesUseCase(settingsService: service)

        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "zebra", auth: .token("tok")))
        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "alpha", auth: .token("tok")))

        let profiles = try listUseCase.execute()
        #expect(profiles.map(\.id) == ["alpha", "zebra"])
    }
}

@Suite("RemoveGitHubProfileUseCase")
struct RemoveGitHubProfileUseCaseTests {
    @Test func removesProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveGitHubProfileUseCase(settingsService: service)
        let removeUseCase = RemoveGitHubProfileUseCase(settingsService: service)
        let listUseCase = ListGitHubProfilesUseCase(settingsService: service)

        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "work", auth: .token("tok")))
        removeUseCase.execute(id: "work")

        let profiles = try listUseCase.execute()
        #expect(profiles.isEmpty)
    }

    @Test func removesOnlySpecifiedProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveGitHubProfileUseCase(settingsService: service)
        let removeUseCase = RemoveGitHubProfileUseCase(settingsService: service)
        let listUseCase = ListGitHubProfilesUseCase(settingsService: service)

        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "profile1", auth: .token("tok1")))
        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "profile2", auth: .token("tok2")))
        removeUseCase.execute(id: "profile1")

        let profiles = try listUseCase.execute()
        #expect(profiles.count == 1)
        #expect(profiles[0].id == "profile2")
    }
}

@Suite("LoadGitHubProfileUseCase")
struct LoadGitHubProfileUseCaseTests {
    @Test func loadsProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveGitHubProfileUseCase(settingsService: service)
        let loadUseCase = LoadGitHubProfileUseCase(settingsService: service)

        try saveUseCase.execute(profile: GitHubCredentialProfile(id: "work", auth: .app(appId: "123", installationId: "456", privateKeyPEM: "pem")))

        let profile = loadUseCase.execute(id: "work")
        #expect(profile?.id == "work")
        guard case .app(let appId, _, _) = profile?.auth else {
            Issue.record("Expected app auth")
            return
        }
        #expect(appId == "123")
    }

    @Test func returnsNilForMissingProfile() {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let loadUseCase = LoadGitHubProfileUseCase(settingsService: service)

        let profile = loadUseCase.execute(id: "nonexistent")
        #expect(profile == nil)
    }
}

@Suite("SaveAnthropicProfileUseCase")
struct SaveAnthropicProfileUseCaseTests {
    @Test func savesProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveAnthropicProfileUseCase(settingsService: service)

        try useCase.execute(profile: AnthropicCredentialProfile(id: "default", apiKey: "sk-ant-123"))

        let loaded = service.loadAnthropicProfile(id: "default")
        #expect(loaded?.apiKey == "sk-ant-123")
    }
}

@Suite("ListAnthropicProfilesUseCase")
struct ListAnthropicProfilesUseCaseTests {
    @Test func listsProfilesAlphabetically() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveAnthropicProfileUseCase(settingsService: service)
        let listUseCase = ListAnthropicProfilesUseCase(settingsService: service)

        try saveUseCase.execute(profile: AnthropicCredentialProfile(id: "zebra", apiKey: "key"))
        try saveUseCase.execute(profile: AnthropicCredentialProfile(id: "alpha", apiKey: "key"))

        let profiles = try listUseCase.execute()
        #expect(profiles.map(\.id) == ["alpha", "zebra"])
    }
}

@Suite("RemoveAnthropicProfileUseCase")
struct RemoveAnthropicProfileUseCaseTests {
    @Test func removesProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveAnthropicProfileUseCase(settingsService: service)
        let removeUseCase = RemoveAnthropicProfileUseCase(settingsService: service)
        let listUseCase = ListAnthropicProfilesUseCase(settingsService: service)

        try saveUseCase.execute(profile: AnthropicCredentialProfile(id: "default", apiKey: "key"))
        removeUseCase.execute(id: "default")

        let profiles = try listUseCase.execute()
        #expect(profiles.isEmpty)
    }
}

@Suite("LoadAnthropicProfileUseCase")
struct LoadAnthropicProfileUseCaseTests {
    @Test func loadsProfile() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveAnthropicProfileUseCase(settingsService: service)
        let loadUseCase = LoadAnthropicProfileUseCase(settingsService: service)

        try saveUseCase.execute(profile: AnthropicCredentialProfile(id: "default", apiKey: "sk-ant-123"))

        let profile = loadUseCase.execute(id: "default")
        #expect(profile?.apiKey == "sk-ant-123")
    }

    @Test func returnsNilForMissingProfile() {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let loadUseCase = LoadAnthropicProfileUseCase(settingsService: service)

        let profile = loadUseCase.execute(id: "nonexistent")
        #expect(profile == nil)
    }
}
