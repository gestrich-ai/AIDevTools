import Foundation
import CredentialService
import UseCaseSDK

public struct RemoveCredentialsUseCase: UseCase {

    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(account: String) throws -> [CredentialStatus] {
        settingsService.removeGitHubProfile(id: account)
        settingsService.removeAnthropicProfile(id: account)
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
