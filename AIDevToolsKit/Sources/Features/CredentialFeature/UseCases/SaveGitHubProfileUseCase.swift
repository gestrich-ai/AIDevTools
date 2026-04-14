import CredentialService
import UseCaseSDK

public struct SaveGitHubProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(profile: GitHubCredentialProfile) throws {
        try settingsService.saveGitHubProfile(profile)
    }
}
