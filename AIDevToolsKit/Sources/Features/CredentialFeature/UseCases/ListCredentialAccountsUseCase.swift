import Foundation
import CredentialService
import UseCaseSDK

public struct ListCredentialAccountsUseCase: UseCase {

    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [String] {
        try settingsService.listCredentialAccounts()
    }
}
