import CredentialService
import UseCaseSDK

public struct LoadAnthropicProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: String) -> AnthropicCredentialProfile? {
        settingsService.loadAnthropicProfile(id: id)
    }
}
