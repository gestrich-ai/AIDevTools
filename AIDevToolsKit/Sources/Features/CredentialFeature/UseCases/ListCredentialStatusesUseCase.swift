import CredentialService
import UseCaseSDK

public struct ListCredentialStatusesUseCase: UseCase {

    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [CredentialStatus] {
        try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
