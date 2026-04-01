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

@Suite("SaveCredentialsUseCase")
struct SaveCredentialsUseCaseTests {
    @Test func savesGitHubTokenAndReturnsStatuses() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveCredentialsUseCase(settingsService: service)

        let statuses = try useCase.execute(
            account: "testaccount",
            gitHubAuth: .token("gh-token-123"),
            anthropicKey: nil
        )

        #expect(statuses.count == 1)
        #expect(statuses[0].account == "testaccount")
        #expect(statuses[0].gitHubAuth == .token)
        #expect(statuses[0].hasAnthropicKey == false)
    }

    @Test func savesAnthropicKeyAndReturnsStatuses() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveCredentialsUseCase(settingsService: service)

        let statuses = try useCase.execute(
            account: "testaccount",
            gitHubAuth: nil,
            anthropicKey: "sk-ant-123"
        )

        #expect(statuses.count == 1)
        #expect(statuses[0].hasAnthropicKey == true)
        #expect(statuses[0].gitHubAuth == .none)
    }

    @Test func savesBothCredentials() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveCredentialsUseCase(settingsService: service)

        let statuses = try useCase.execute(
            account: "testaccount",
            gitHubAuth: .token("gh-token"),
            anthropicKey: "sk-ant-123"
        )

        #expect(statuses.count == 1)
        #expect(statuses[0].gitHubAuth == .token)
        #expect(statuses[0].hasAnthropicKey == true)
    }

    @Test func emptyAnthropicKeyIsNotSaved() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let useCase = SaveCredentialsUseCase(settingsService: service)

        let statuses = try useCase.execute(
            account: "testaccount",
            gitHubAuth: nil,
            anthropicKey: ""
        )

        #expect(statuses.isEmpty)
    }
}

@Suite("RemoveCredentialsUseCase")
struct RemoveCredentialsUseCaseTests {
    @Test func removesAccountAndReturnsEmptyStatuses() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveCredentialsUseCase(settingsService: service)
        let removeUseCase = RemoveCredentialsUseCase(settingsService: service)

        try saveUseCase.execute(account: "testaccount", gitHubAuth: .token("tok"), anthropicKey: "key")
        let statuses = try removeUseCase.execute(account: "testaccount")

        #expect(statuses.isEmpty)
    }

    @Test func removesOnlySpecifiedAccount() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveCredentialsUseCase(settingsService: service)
        let removeUseCase = RemoveCredentialsUseCase(settingsService: service)

        try saveUseCase.execute(account: "account1", gitHubAuth: .token("tok1"), anthropicKey: nil)
        try saveUseCase.execute(account: "account2", gitHubAuth: .token("tok2"), anthropicKey: nil)
        let statuses = try removeUseCase.execute(account: "account1")

        #expect(statuses.count == 1)
        #expect(statuses[0].account == "account2")
    }
}

@Suite("ListCredentialAccountsUseCase")
struct ListCredentialAccountsUseCaseTests {
    @Test func listsAccountsAlphabetically() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveCredentialsUseCase(settingsService: service)
        let listUseCase = ListCredentialAccountsUseCase(settingsService: service)

        try saveUseCase.execute(account: "zebra", gitHubAuth: .token("tok"), anthropicKey: nil)
        try saveUseCase.execute(account: "alpha", gitHubAuth: .token("tok"), anthropicKey: nil)

        let accounts = try listUseCase.execute()
        #expect(accounts == ["alpha", "zebra"])
    }
}

@Suite("LoadCredentialStatusUseCase")
struct LoadCredentialStatusUseCaseTests {
    @Test func loadsStatusForAccount() throws {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let saveUseCase = SaveCredentialsUseCase(settingsService: service)
        let loadUseCase = LoadCredentialStatusUseCase(settingsService: service)

        try saveUseCase.execute(
            account: "testaccount",
            gitHubAuth: .app(appId: "123", installationId: "456", privateKeyPEM: "key"),
            anthropicKey: "sk-ant"
        )

        let status = loadUseCase.execute(account: "testaccount")
        #expect(status.account == "testaccount")
        #expect(status.gitHubAuth == .app)
        #expect(status.hasAnthropicKey == true)
    }

    @Test func returnsNoneForMissingAccount() {
        let service = SecureSettingsService(keychain: MockKeychainStore())
        let loadUseCase = LoadCredentialStatusUseCase(settingsService: service)

        let status = loadUseCase.execute(account: "nonexistent")
        #expect(status.gitHubAuth == .none)
        #expect(status.hasAnthropicKey == false)
    }
}
