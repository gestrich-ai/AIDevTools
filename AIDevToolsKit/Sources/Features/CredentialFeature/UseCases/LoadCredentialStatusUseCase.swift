import Foundation
import CredentialService
import UseCaseSDK

public struct LoadCredentialStatusUseCase: UseCase {

    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String) -> CredentialStatus {
        CredentialStatusLoader(settingsService: settingsService).loadStatus(account: account)
    }
}
