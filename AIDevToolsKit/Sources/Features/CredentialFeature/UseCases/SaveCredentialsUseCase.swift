import Foundation
import CredentialService
import UseCaseSDK

public struct SaveCredentialsUseCase: UseCase {

    private let settingsService: SecureSettingsService

    public init(settingsService: SecureSettingsService) {
        self.settingsService = settingsService
    }

    @discardableResult
    public func execute(
        account: String,
        gitHubAuth: GitHubAuth?,
        anthropicKey: String?
    ) throws -> [CredentialStatus] {
        if let gitHubAuth {
            try settingsService.saveGitHubProfile(GitHubCredentialProfile(id: account, auth: gitHubAuth))
        }
        if let anthropicKey, !anthropicKey.isEmpty {
            try settingsService.saveAnthropicProfile(AnthropicCredentialProfile(id: account, apiKey: anthropicKey))
        }
        return try CredentialStatusLoader(settingsService: settingsService).loadAllStatuses()
    }
}
