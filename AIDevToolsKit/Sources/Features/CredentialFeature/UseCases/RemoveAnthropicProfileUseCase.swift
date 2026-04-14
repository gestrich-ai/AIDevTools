import CredentialService
import UseCaseSDK

public struct RemoveAnthropicProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(id: String) {
        settingsService.removeAnthropicProfile(id: id)
    }
}
