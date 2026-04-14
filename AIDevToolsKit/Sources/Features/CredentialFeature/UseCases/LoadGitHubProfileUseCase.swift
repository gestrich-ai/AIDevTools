import CredentialService
import UseCaseSDK

public struct LoadGitHubProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: String) -> GitHubCredentialProfile? {
        settingsService.loadGitHubProfile(id: id)
    }
}
