import Foundation
import CredentialService

public struct LoadCredentialStatusUseCase: Sendable {

    private let settingsService: CredentialSettingsService

    public init(settingsService: CredentialSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(account: String) -> CredentialStatus {
        CredentialStatusLoader(settingsService: settingsService).loadStatus(account: account)
    }
}
