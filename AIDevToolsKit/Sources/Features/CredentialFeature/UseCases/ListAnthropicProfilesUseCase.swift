import CredentialService
import UseCaseSDK

public struct ListAnthropicProfilesUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute() throws -> [AnthropicCredentialProfile] {
        let ids = try settingsService.listAnthropicProfileIds()
        return ids.compactMap { settingsService.loadAnthropicProfile(id: $0) }
    }
}
