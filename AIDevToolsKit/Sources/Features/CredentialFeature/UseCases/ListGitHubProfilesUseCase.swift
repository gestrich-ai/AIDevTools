import CredentialService
import UseCaseSDK

public struct ListGitHubProfilesUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [GitHubCredentialProfile] {
        let ids = try settingsService.listGitHubProfileIds()
        return ids.compactMap { settingsService.loadGitHubProfile(id: $0) }
    }
}
