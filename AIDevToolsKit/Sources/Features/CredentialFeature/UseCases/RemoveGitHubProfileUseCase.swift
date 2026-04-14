import CredentialService
import UseCaseSDK

public struct RemoveGitHubProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: String) {
        settingsService.removeGitHubProfile(id: id)
    }
}
