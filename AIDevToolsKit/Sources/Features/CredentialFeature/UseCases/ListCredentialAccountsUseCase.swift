import Foundation
import CredentialService

public struct ListCredentialAccountsUseCase: Sendable {

    private let settingsService: CredentialSettingsService

    public init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [String] {
        try settingsService.listCredentialAccounts()
    }
}
