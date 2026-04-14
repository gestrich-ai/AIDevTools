import CredentialService
import UseCaseSDK

public struct SaveAnthropicProfileUseCase: UseCase {
    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    public func execute(profile: AnthropicCredentialProfile) throws {
        try settingsService.saveAnthropicProfile(profile)
    }
}
